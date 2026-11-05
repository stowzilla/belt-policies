# frozen_string_literal: true

class SpecActiveItemAcceptance < ActiveItem::Base
  include Belt::Policies::AcceptanceRecord

  self.table_name = 'spec-policy-acceptances'
end

RSpec.describe Belt::Policies::AcceptanceRecord do
  let(:client) { Aws::DynamoDB::Client.new(stub_responses: true) }

  before { SpecActiveItemAcceptance.dynamodb = client }

  # fp:expire_deleted_acceptances
  it 'scans for rows deleted before the cutoff one page at a time' do
    client.stub_responses(:scan, [
                            { items: [{ 'id' => 'a', 'userId' => 'u1', 'accountDeletedAt' => '2026-01-01T00:00:00Z' }],
                              last_evaluated_key: { 'id' => 'a' } },
                            { items: [{ 'id' => 'b', 'userId' => 'u2', 'accountDeletedAt' => '2026-02-01T00:00:00Z' }] }
                          ])
    pages = []
    SpecActiveItemAcceptance.deleted_before('2027-01-01T00:00:00Z') { |rows| pages << rows.map(&:user_id) }

    expect(pages).to eq([%w[u1], %w[u2]])
    scans = client.api_requests.select { |r| r[:operation_name] == :scan }.map { |r| r[:params] }
    expect(scans.first).to include(filter_expression: '#deleted < :cutoff',
                                   expression_attribute_names: { '#deleted' => 'accountDeletedAt' })
    expect(scans.last[:exclusive_start_key]).to eq('id' => { s: 'a' })
  end
end
