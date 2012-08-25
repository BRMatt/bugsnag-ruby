module Bugsnag
  class Rack
    def initialize(app)
      @app = app

      # Automatically set the release_stage
      Bugsnag.configuration.release_stage = ENV['RACK_ENV'] if ENV['RACK_ENV']

      # Automatically set the project_root if possible
      if Bugsnag.configuration.project_root.nil? || Bugsnag.configuration.project_root.empty?
        if defined?(settings)
          Bugsnag.configuration.project_root = settings.root
        else
          caller.each do |c|
            if c =~ /[\/\\]config.ru$/
              Bugsnag.configuration.project_root = File.dirname(c.split(":").first)
              break
            end
          end
        end
      end
    end

    def call(env)
      begin
        # Set up the callback for extracting the rack request data
        # This callback is only excecuted when Bugsnag.notify is called
        Bugsnag.request_configuration.meta_data_callback = lambda {
          request = ::Rack::Request.new(env)

          session = env["rack.session"]
          params = env["action_dispatch.request.parameters"] || request.params

          # Automatically set any params_filters from the rack env (once only)
          unless @rack_filters
            @rack_filters = env["action_dispatch.parameter_filter"]
            Bugsnag.configuration.params_filters += @rack_filters
          end

          # Automatically set user_id and context if possible
          Bugsnag.request_configuration.user_id ||= session[:session_id] || session["session_id"] if session
          Bugsnag.request_configuration.context ||= Bugsnag::Helpers.param_context(params) || Bugsnag::Helpers.request_context(request)

          # Fill in the request meta-data
          {
            :request => {
              :url => request.url,
              :controller => params[:controller],
              :action => params[:action],
              :params => params.to_hash,
            },
            :session => session,
            :environment => env
          }
        }

        begin
          response = @app.call(env)
        rescue Exception => raised
          # Notify bugsnag of rack exceptions
          Bugsnag.auto_notify(raised)

          # Re-raise the exception
          raise
        end

        # Notify bugsnag of rack exceptions
        if env["rack.exception"]
          Bugsnag.auto_notify(env["rack.exception"])
        end
      ensure
        # Clear per-request data after processing the each request
        Bugsnag.clear_request_config
      end

      response
    end
  end
end
