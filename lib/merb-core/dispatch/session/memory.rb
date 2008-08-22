module Merb
  
  # Sessions stored in memory.
  #
  # Set it up by adding the following to your init file:
  #
  #  Merb::Config.use do |c|
  #    c[:session_store]      = :memory
  #    c[:memory_session_ttl] = 3600 # in seconds, one hour
  #  end
  #
  # Sessions will remain in memory until the server is stopped or the time
  # as set in :memory_session_ttl expires.
  class MemorySession < SessionStore
    
    class << self

      # Generates a new session ID and creates a new session.
      #
      # ==== Returns
      # MemorySession:: The new session.
      def generate
        sid = Merb::SessionMixin.rand_uuid
        session = new(sid)
        session.needs_new_cookie = true
        MemorySessionContainer[sid] = session
      end
      
      # Setup a new session.
      #
      # ==== Parameters
      # request<Merb::Request>:: The Merb::Request that came in from Rack.
      #
      # ==== Returns
      # SessionStore:: a SessionStore. If no sessions were found, 
      # a new SessionStore will be generated.
      def setup(request)
        session = unless (session_id = request.session_id).blank?
          MemorySessionContainer[session_id] || generate
        else
          generate
        end
        request.session = session
        session
      end
      
      # ==== Returns
      # Symbol:: The session store type, i.e. :memory.
      def session_store_type
        :memory
      end
      
    end
    
    # Teardown and/or persist the current session.
    #
    # ==== Parameters
    # request<Merb::Request>:: The Merb::Request that came in from Rack.
    def finalize(request)
      if needs_new_cookie || Merb::SessionMixin.needs_new_cookie
        request.set_session_id_cookie(session_id)
      end
    end
    
    # Regenerate the Session ID
    def regenerate
      new_sid = Merb::SessionMixin.rand_uuid 
      old_sid = session_id
      MemorySessionContainer[new_sid] = MemorySessionContainer.delete(old_sid)
      self.session_id = new_sid
    end
    
  end
  
  # Used for handling multiple sessions stored in memory.
  class MemorySessionContainer
    class << self

      # ==== Parameters
      # ttl<Fixnum>:: Session validity time in seconds. Defaults to 1 hour.
      #
      # ==== Returns
      # MemorySessionContainer:: The new session container.
      def setup(ttl=nil)
        @sessions = Hash.new
        @timestamps = Hash.new
        @mutex = Mutex.new
        @session_ttl = ttl || 60*60 # default 1 hour
        start_timer
        self
      end

      # ==== Parameters
      # key<String>:: ID of the session to retrieve.
      #
      # ==== Returns
      # MemorySession:: The session corresponding to the ID.
      def [](key)
        @mutex.synchronize {
          @timestamps[key] = Time.now
          @sessions[key]
        }
      end

      # ==== Parameters
      # key<String>:: ID of the session to set.
      # val<MemorySession>:: The session to set.
      def []=(key, val) 
        @mutex.synchronize {
          @timestamps[key] = Time.now
          @sessions[key] = val
        }
      end

      # ==== Parameters
      # key<String>:: ID of the session to delete.
      def delete(key)
        @mutex.synchronize {
          @timestamps.delete(key)
          @sessions.delete(key)
        }
      end

      # Deletes any sessions that have reached their maximum validity.
      def reap_old_sessions
        @timestamps.each do |key,stamp|
          if stamp + @session_ttl < Time.now
            delete(key)
          end  
        end
        GC.start
      end

      # Starts the timer that will eventually reap outdated sessions.
      def start_timer
        Thread.new do
          loop {
            sleep @session_ttl
            reap_old_sessions
          } 
        end  
      end

      # ==== Returns
      # Array:: The sessions stored in this container.
      def sessions
        @sessions
      end  
      
    end # end singleton class

  end # end MemorySessionContainer
end