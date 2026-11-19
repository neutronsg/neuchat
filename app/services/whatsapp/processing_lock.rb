require 'digest'

# Session locks cover channel HTTP calls without holding a database transaction open.
# Always use the same checked-out connection for acquisition and release.
class Whatsapp::ProcessingLock
  def self.synchronize(key)
    lock_id = Digest::SHA256.digest("whatsapp:#{key}").unpack1('q>')
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      acquired = false
      begin
        connection.execute("SELECT pg_advisory_lock(#{lock_id})")
        acquired = true
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{lock_id})") if acquired && connection.active?
      end
    end
  end
end
