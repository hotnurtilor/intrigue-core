module Intrigue
  module Task
    class SiemensMiniwebDefaultLogin < BaseTask
      include Intrigue::Task::Web
      include Intrigue::Task::BruteForceLoginHelper
      require 'uri'

      def self.metadata
        {
          name: 'vuln/bruteforce/siemens_miniweb_login_vuln',
          pretty_name: 'Bruteforce - Siemens Miniweb Default Login Credentials',
          authors: [''],
          description: 'Bruteforce Siemens Miniweb Default Login Credentials',
          type: 'Vuln',
          passive: false,
          allowed_types: ['Uri'],
          example_entities: [
            { 'type' => 'Uri', 'details' => { 'name' => 'http://intrigue.io' } }
          ],
          affected_software: [
            {
              vendor: 'Siemens',
              product: 'Miniweb'
            }
          ],
          allowed_options: [
            { name: 'threads', regex: 'integer', default: 10 }
          ],
          created_types: ['Uri']
        }
      end

      def run
        super
        require_enrichment

        fingerprint = _get_entity_detail('fingerprint')

        return false unless vendor?(fingerprint,
                                    'Siemens') && is_product?(fingerprint,
                                                              'Miniweb') && tag?(fingerprint, 'Login Panel')

        credentials = [
          {
            user: 'Administrator',
            password: '100'
          }
        ]

        uri = URI(_get_entity_name)
        base_uri = "#{uri.scheme}://#{uri.host}:#{uri.port}"

        task_information = {
          http_method: :post,
          uri: "#{base_uri}/FormLogin",
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded',
                     'Origin' => base_uri.to_s,
                     'Referer' => "#{base_uri}/start.html" },
          data: {
            'Token' => '%=Token',
            'Redirection' => "#{base_uri}/start.html"
          },
          follow_redirects: true,
          timeout: 10,
          thread_count: _get_option('threads')
        }

        # brute with force.
        brute_force_data = bruteforce_login(task_information, credentials, method(:validator),
                                            method(:build_post_request))

        unless brute_force_data[:credentials].empty?

          _log 'Creating issue'

          _create_linked_issue 'default_login_credentials',
                               {
                                 proof: {
                                   "Successful login credentials": brute_force_data[:credentials],
                                   "Responses": brute_force_data[:responses]
                                 }
                               }
        end
      end

      # custom validator, each default login task will have its own.
      # some tasks might require a more complex approach.
      def validator(response, task_information)

        if response.headers['Set-Cookie'].nil?
          task_information[:headers]['Cookie'] = 'siemens_ad_secure_session=; siemens_ad_session=;'

        else

          siemens_ad_session = response.headers['Set-Cookie'].to_s.match(/siemens_ad_session=(.*?);/i)

          if siemens_ad_session.nil?
            _log_debug "Unable to fetch cookie, Set-Cookie: #{response.headers['Set-Cookie']}"
            task_information[:headers]['Cookie'] = 'siemens_ad_secure_session=; siemens_ad_session=;'
          else
            _log_debug "Got siemens_ad_session cookie: #{siemens_ad_session[1]}"

            task_information[:headers]['Cookie'] =
              "siemens_ad_secure_session=; siemens_ad_session=#{siemens_ad_session[1]};"
          end

        end

        _log_debug response.headers

        get_response = http_request :get, task_information[:data]['Redirection'], nil, task_information[:headers]

        get_response.body_utf8.match(/You are logged in\./i)
      end

      def build_post_request(task_information, credential)
        response = http_request :get, task_information[:uri]

        unless response.headers['Set-Cookie'].nil?

          siemens_ad_session = response.headers['Set-Cookie'].to_s.match(/siemens_ad_session=(.*?);/i)

          if siemens_ad_session.nil?
            _log_debug "Unable to fetch cookie, Set-Cookie: #{response.headers['Set-Cookie']}"
          else
            _log_debug "Got siemens_ad_session cookie: #{siemens_ad_session[1]}"
            task_information[:headers]['Cookie'] = "siemens_ad_session=#{siemens_ad_session[1]};"
          end

        end
        # if we can't find the cookie, try anyway.

        task_information[:data]['Login'] = credential[:user]
        task_information[:data]['Password'] = credential[:password]

        true
      end
    end
  end
end
