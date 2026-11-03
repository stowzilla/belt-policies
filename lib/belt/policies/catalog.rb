# frozen_string_literal: true

module Belt
  module Policies
    # The kinds of policy `belt g policy` knows how to outline. Each is a
    # title, whether people must agree to it, and the section headings with a
    # prompt for what usually goes there. The prompts are reminders of topics,
    # not legal text: nothing here was written or reviewed by a lawyer.
    module Catalog
      Kind = Struct.new(:slug, :title, :aliases, :requires_acceptance, :summary, :sections, keyword_init: true)

      KINDS = [
        Kind.new(
          slug: 'terms-of-service', title: 'Terms of Service', aliases: %w[terms tos terms-of-use],
          requires_acceptance: true,
          summary: 'The agreement between you and the people who use your app.',
          sections: {
            'Who we are' => 'The legal entity offering the service, and how to contact it.',
            'Accepting these terms' => 'How someone agrees (for example a checkbox at sign-up) and who may agree.',
            'Your account' => 'Eligibility, age limits, account security, and what happens to inactive accounts.',
            'Using the service' => 'What people may and may not do. Link an Acceptable Use Policy if you have one.',
            'Payments, renewals and refunds' => 'Prices, billing cycles, auto-renewal, cancellation, refunds. ' \
                                                'Remove if the app is free.',
            'Content you provide' => 'Who owns what people upload, and the licence they grant you to run the service.',
            'Our intellectual property' => 'What you own, and what people may not copy or reuse.',
            'Third-party services' => 'Services you rely on or link to, and that their terms apply.',
            'Termination' => 'When either side can end the agreement, and what survives.',
            'Disclaimers' => 'What you do not promise about the service.',
            'Limitation of liability' => 'Limits on what you owe if something goes wrong, as far as the law allows.',
            'Disputes and governing law' => 'Which law applies and where disputes are resolved.',
            'Changes to these terms' => 'How you announce changes and whether people must agree again.',
            'Contact' => 'Where to send questions about these terms.'
          }
        ),
        Kind.new(
          slug: 'privacy-policy', title: 'Privacy Policy', aliases: %w[privacy privacy-notice],
          requires_acceptance: true,
          summary: 'What personal data you collect, why, who sees it, and how long you keep it.',
          sections: {
            'Who we are' => 'The organisation responsible for the data, and a privacy contact.',
            'What we collect' => 'Each kind of data: what people give you, what is collected automatically, ' \
                                 'and what comes from others. Match it to what your tables actually store.',
            'How we use it' => 'Each purpose, and (where required) the legal basis for it.',
            'Who we share it with' => 'Processors and other recipients (hosting, email, payments, analytics).',
            'Cookies and similar technology' => 'What you use, or link the Cookie Policy.',
            'How long we keep it' => 'A retention period for each kind of data, including acceptance records.',
            'Your choices and rights' => 'Access, correction, deletion, export, opting out, and how to ask.',
            'Security' => 'How you protect the data, in general terms.',
            'Children' => 'Minimum age and what happens if you learn a child signed up.',
            'International transfers' => 'Where the data is stored and processed.',
            'Changes to this policy' => 'How you announce changes.',
            'Contact' => 'Where to send privacy questions and requests.'
          }
        ),
        Kind.new(
          slug: 'cookie-policy', title: 'Cookie Policy', aliases: %w[cookies],
          requires_acceptance: false,
          summary: 'The cookies and local storage your app uses and how to control them.',
          sections: {
            'What cookies are' => 'A short plain-language explanation.',
            'Cookies we use' => 'Each cookie or storage key: name, purpose, who sets it, and how long it lasts.',
            'Managing cookies' => 'How to change preferences in your app and in the browser.',
            'Changes' => 'How you announce changes.',
            'Contact' => 'Where to send questions.'
          }
        ),
        Kind.new(
          slug: 'acceptable-use-policy', title: 'Acceptable Use Policy', aliases: %w[aup acceptable-use],
          requires_acceptance: false,
          summary: 'What people may not do with your service.',
          sections: {
            'Scope' => 'Who and what this policy covers, and how it relates to the Terms.',
            'Prohibited uses' => 'Illegal activity, abuse, spam, security testing without permission, and so on.',
            'Content rules' => 'What may not be posted or shared.',
            'Enforcement' => 'What you may do when the policy is broken.',
            'Reporting' => 'How to report a violation.'
          }
        ),
        Kind.new(
          slug: 'community-guidelines', title: 'Community Guidelines', aliases: %w[community guidelines],
          requires_acceptance: false,
          summary: 'How people are expected to treat each other in your app.',
          sections: {
            'What we expect' => 'The behaviour you want to see.',
            'What is not allowed' => 'Harassment, hate, cheating, impersonation, and so on.',
            'Names and profiles' => 'Rules for usernames, pictures, and bios.',
            'Moderation' => 'How reports are reviewed and what actions you may take.',
            'Appeals' => 'How someone can ask you to reconsider.'
          }
        ),
        Kind.new(
          slug: 'refund-policy', title: 'Refund Policy', aliases: %w[refunds returns cancellation-policy],
          requires_acceptance: false,
          summary: 'When and how people get their money back.',
          sections: {
            'Eligibility' => 'What can be refunded and within what time.',
            'Subscriptions and cancellation' => 'What happens to the current period when someone cancels.',
            'How to request a refund' => 'The steps and what information you need.',
            'Processing' => 'How long refunds take and how they are paid.',
            'Contact' => 'Where to send refund questions.'
          }
        ),
        Kind.new(
          slug: 'eula', title: 'End User License Agreement', aliases: %w[license end-user-license-agreement],
          requires_acceptance: true,
          summary: 'The licence to install and use downloadable or mobile software.',
          sections: {
            'Licence grant' => 'What the user may do with the software, and on how many devices.',
            'Restrictions' => 'Reverse engineering, redistribution, and so on.',
            'Ownership' => 'That the software is licensed, not sold.',
            'App store terms' => 'Terms the app stores require you to include, if you distribute through them.',
            'Updates' => 'How updates are delivered and whether they are required.',
            'Termination' => 'When the licence ends.',
            'Disclaimers and liability' => 'What you do not promise, as far as the law allows.',
            'Contact' => 'Where to send questions.'
          }
        ),
        Kind.new(
          slug: 'seller-agreement', title: 'Seller Agreement', aliases: %w[marketplace-seller-agreement seller],
          requires_acceptance: true,
          summary: 'Extra terms for people who sell through your marketplace.',
          sections: {
            'Who can sell' => 'Eligibility and verification.',
            'Listings' => 'What may be listed and how it must be described.',
            'Fees and payouts' => 'Commissions, payout timing, taxes, and chargebacks.',
            'Fulfilment' => 'Shipping, handover, and service levels.',
            'Returns and disputes' => 'How buyer complaints are handled.',
            'Suspension and termination' => 'When you may remove a seller.',
            'Contact' => 'Where sellers send questions.'
          }
        ),
        Kind.new(
          slug: 'data-processing-agreement', title: 'Data Processing Agreement', aliases: %w[dpa],
          requires_acceptance: true,
          summary: 'Terms for processing personal data on behalf of business customers.',
          sections: {
            'Roles' => 'Who is the controller and who is the processor.',
            'Processing details' => 'Subject matter, duration, nature, purpose, data types, and data subjects.',
            'Processor obligations' => 'Instructions, confidentiality, security, and assistance.',
            'Sub-processors' => 'The list of sub-processors and how changes are announced.',
            'International transfers' => 'Transfer mechanisms, where they apply.',
            'Breach notification' => 'How and when you notify the customer.',
            'Deletion and return' => 'What happens to the data when the contract ends.',
            'Audits' => 'How the customer can check compliance.'
          }
        ),
        Kind.new(
          slug: 'sms-terms', title: 'SMS Terms', aliases: %w[sms text-messaging messaging-terms],
          requires_acceptance: true,
          summary: 'Consent and terms for text messages (pairs with belt-messaging).',
          sections: {
            'Program description' => 'What messages people get and how often.',
            'Consent' => 'How people opt in, and that consent is not a condition of purchase.',
            'Opting out and help' => 'Reply STOP to cancel and HELP for help.',
            'Costs' => 'That message and data rates may apply.',
            'Carriers' => 'That carriers are not liable for delayed or undelivered messages.',
            'Privacy' => 'Link the Privacy Policy.',
            'Contact' => 'Where to send questions.'
          }
        ),
        Kind.new(
          slug: 'accessibility-statement', title: 'Accessibility Statement', aliases: %w[accessibility a11y],
          requires_acceptance: false,
          summary: 'Your commitment to accessibility and how to report barriers.',
          sections: {
            'Our commitment' => 'The standard you aim for (for example WCAG 2.2 AA).',
            'Known limitations' => 'Parts of the app that are not yet accessible.',
            'Feedback' => 'How to report a barrier, and how quickly you respond.'
          }
        ),
        Kind.new(
          slug: 'do-not-sell', title: 'Do Not Sell or Share My Personal Information', aliases: %w[ccpa opt-out],
          requires_acceptance: false,
          summary: 'How people opt out of the sale or sharing of their personal information.',
          sections: {
            'What this covers' => 'What "sale" and "sharing" mean for your app, or that you do neither.',
            'How to opt out' => 'The form, link, or global privacy control signal you honour.',
            'Verification' => 'What you need to confirm a request.',
            'Contact' => 'Where to send requests.'
          }
        )
      ].freeze

      module_function

      def all
        KINDS
      end

      # A kind by slug or alias ('tos', 'privacy', 'terms_of_service', …), or nil.
      def find(name)
        key = normalize(name)
        KINDS.find { |kind| kind.slug == key || kind.aliases.include?(key) }
      end

      def normalize(name)
        name.to_s.strip.downcase.tr('_ ', '--').gsub(/[^a-z0-9-]/,
                                                     '').squeeze('-').delete_prefix('-').delete_suffix('-')
      end
    end
  end
end
