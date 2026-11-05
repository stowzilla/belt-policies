# frozen_string_literal: true

require 'json'

class SpecPoliciesController < BeltController::Base
  include Belt::Policies::Controller
end

class SpecGuardedController < BeltController::Base
  include Belt::Policies::RequireAcceptance

  before_action :require_current_policies!

  def index
    success_response(ok: true)
  end
end

class SpecPickyPoliciesController < BeltController::Base
  include Belt::Policies::Controller

  private

  def policies_may_accept?(subject_id)
    subject_id != 'someone-elses-child'
  end
end

class SpecPartlyGuardedController < BeltController::Base
  include Belt::Policies::RequireAcceptance

  before_action :require_current_policies!, except: %i[play]

  def play
    success_response(ok: true)
  end
end

class SpecGuardedPoliciesController < SpecGuardedController
  include Belt::Policies::Controller
end

RSpec.describe Belt::Policies::Controller do
  before do
    FakePolicyVersion.publish('terms-of-service', '2026-11-02', content: "# Terms\n")
    FakePolicyVersion.publish('terms-of-service', '2026-01-01', published_at: '2026-01-01T00:00:00Z',
                                                                content: "# Old\n")
    FakePolicyVersion.publish('cookie-policy', '1', requires_acceptance: false)
  end

  def call(action, controller: SpecPoliciesController, user: nil, path: {}, query: {}, body: {})
    context = { 'identity' => { 'sourceIp' => '203.0.113.7' } }
    context['authorizer'] = { 'claims' => { 'sub' => user, 'email' => "#{user}@example.com" } } if user
    event = {
      'headers' => { 'User-Agent' => 'Spec Browser 1.0' }, 'requestContext' => context,
      'pathParameters' => path, 'queryStringParameters' => query
    }
    response = controller.new(event: event, body: body).dispatch(action)
    [response[:statusCode], JSON.parse(response[:body])]
  end

  # fp:current_policy_version
  it 'lists the current version of every policy' do
    status, body = call(:index)
    expect(status).to eq(200)
    expect(body['policies'].map { |p| [p['policy'], p['version']] })
      .to eq([%w[cookie-policy 1], %w[terms-of-service 2026-11-02]])
    expect(body['policies'].first).not_to have_key('content')
  end

  # fp:current_policy_version
  it "shows a policy's current text, or an older version on request" do
    _, current = call(:show, path: { 'slug' => 'terms-of-service' })
    expect(current['policy']).to include('version' => '2026-11-02', 'content' => "# Terms\n", 'current' => true)

    _, old = call(:show, path: { 'slug' => 'terms-of-service' }, query: { 'version' => '2026-01-01' })
    expect(old['policy']).to include('content' => "# Old\n", 'current' => false)

    expect(call(:show, path: { 'slug' => 'nope' }).first).to eq(404)
  end

  # fp:record_policy_acceptance
  it 'records an acceptance with the email, IP and browser from the request' do
    status, body = call(:accept, user: 'user-1',
                                 body: { 'policies' => [{ 'policy' => 'terms-of-service', 'version' => '2026-11-02' }],
                                         'via' => 'signup' })
    expect(status).to eq(200)
    expect(body['pending']).to eq([])
    expect(FakePolicyAcceptance.rows.last).to have_attributes(
      user_id: 'user-1', email: 'user-1@example.com', ip_address: '203.0.113.7',
      user_agent: 'Spec Browser 1.0', accepted_via: 'signup'
    )
  end

  it 'accepts a single policy and version' do
    status, = call(:accept, user: 'user-1', body: { 'policy' => 'terms-of-service', 'version' => '2026-11-02' })
    expect(status).to eq(200)
    expect(FakePolicyAcceptance.rows.size).to eq(1)
  end

  # fp:reject_stale_policy_version
  it 'answers 409 when the version shown is no longer current' do
    stale = [{ 'policy' => 'terms-of-service', 'version' => '2026-01-01' }]
    status, body = call(:accept, user: 'user-1', body: { 'policies' => stale })
    expect(status).to eq(409)
    expect(body.dig('details', 'current_version')).to eq('2026-11-02')
    expect(FakePolicyAcceptance.rows).to be_empty
  end

  # fp:record_policy_acceptance
  it 'answers 422 for unknown policies or an empty request, and 401 without a user' do
    expect(call(:accept, user: 'user-1', body: { 'policies' => ['made-up'] }).first).to eq(422)
    expect(call(:accept, user: 'user-1', body: {}).first).to eq(422)
    expect(call(:accept, body: { 'policies' => ['terms-of-service'] }).first).to eq(401)
    expect(call(:status).first).to eq(401)
  end

  # fp:record_subject_acceptance
  it 'records an acceptance about a subject and reports that subject\'s status' do
    status, body = call(:accept, user: 'parent-1',
                                 body: { 'policies' => ['terms-of-service'], 'subject_id' => 'child-a',
                                         'metadata' => { 'terms_version' => '3' } })
    expect(status).to eq(200)
    expect(body['pending']).to eq([])
    expect(FakePolicyAcceptance.rows.last).to have_attributes(subject_id: 'child-a',
                                                              metadata: { 'terms_version' => '3' })

    expect(call(:status, user: 'parent-1').last['pending']).to eq(%w[terms-of-service])
    expect(call(:status, user: 'parent-1', query: { 'subject_id' => 'child-a' }).last['pending']).to eq([])
  end

  # fp:refuse_policy_acceptance
  it 'answers 403 and records nothing when the app refuses the acceptance' do
    status, body = call(:accept, controller: SpecPickyPoliciesController, user: 'parent-1',
                                 body: { 'policies' => ['terms-of-service'], 'subject_id' => 'someone-elses-child' })
    expect(status).to eq(403)
    expect(body.dig('details', 'code')).to eq('acceptance_not_allowed')
    expect(FakePolicyAcceptance.rows).to be_empty
  end

  it "reports the signed-in user's pending policies" do
    _, body = call(:status, user: 'user-1')
    expect(body['pending']).to eq(%w[terms-of-service])
  end

  # fp:require_current_policies
  describe Belt::Policies::RequireAcceptance do
    it 'stops a signed-in user with pending policies, listing them' do
      status, body = call(:index, controller: SpecGuardedController, user: 'user-1')
      expect(status).to eq(403)
      expect(body.dig('details', 'code')).to eq('policies_pending')
      expect(body.dig('details', 'pending').map { |p| p['policy'] }).to eq(%w[terms-of-service])
    end

    it 'lets them through once accepted, and never blocks anonymous requests' do
      Belt::Policies.accept!(user_id: 'user-1', policies: %w[terms-of-service], via: 'prompt')
      expect(call(:index, controller: SpecGuardedController, user: 'user-1').first).to eq(200)
      expect(call(:index, controller: SpecGuardedController).first).to eq(200)
    end

    it 'leaves actions excluded with except: open' do
      expect(call(:play, controller: SpecPartlyGuardedController, user: 'user-1').first).to eq(200)
    end

    it 'leaves the policies routes open so pending users can accept' do
      status, = call(:accept, controller: SpecGuardedPoliciesController, user: 'user-1',
                              body: { 'policies' => ['terms-of-service'] })
      expect(status).to eq(200)
    end
  end
end
