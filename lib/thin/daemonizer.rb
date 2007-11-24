require 'etc'

module Thin
  # Creator of external processes to run the server in the background.
  class Daemonizer
    attr_accessor :pid_file, :timeout
    
    def initialize(pid_file, timeout=60)
      raise ArgumentError, 'PID file required' unless pid_file
      @pid_file = File.expand_path(pid_file)
      @timeout = timeout
    end
    
    # Kill the process which PID is stored in +pid_file+.
    def kill
      if File.exist?(@pid_file) && pid = open(@pid_file).read
        print "Sending INT signal to process #{pid} ... "
        begin
          Process.kill('INT', pid.to_i)
          Timeout.timeout(@timeout) do
            sleep 0.5 until !File.exist?(@pid_file)
          end
        rescue Timeout::Error
          print "timeout! Sending KILL signal ... "
          Process.kill('KILL', pid.to_i)
          remove_pid_file
        end
        puts "stopped!"
      else
        puts "Can't stop process, no PID found in #{@pid_file}"
      end
    rescue Errno::ESRCH # No such process
      puts "process not found!"
      remove_pid_file
    end
    
    # Starts the server in a seperate process
    # returning the control right away.
    def daemonize(title=nil)
      print "Starting #{title} ... "
      pid = fork do
        pwd = Dir.pwd
        # Prepares the process environment.
        # Taken from ActiveSupport::Kernel#daemonize
        exit if fork                   # Parent exits, child continues.
        Process.setsid                 # Become session leader.
        exit if fork                   # Zap session leader. See [1].
        Dir.chdir "/"                  # Release old working directory.
        File.umask 0000                # Ensure sensible umask. Adjust as needed.
        STDIN.reopen "/dev/null"       # Free file descriptors and
        STDOUT.reopen "/dev/null", "a" # point them somewhere sensible.
        STDERR.reopen STDOUT           # STDOUT/ERR should better go to a logfile.
        
        trap('HUP', 'IGNORE') # Don't die upon logout
        
        Dir.chdir pwd
        write_pid_file
        at_exit { remove_pid_file }
        yield self
        exit
      end
      puts "started in process #{pid}"

      # Make sure we do not create zombies
      Process.detach(pid)
      pid
    end
    
    # Change privileges of the process to specified user and group.
    def change_privilege(user, group)
      uid, gid = Process.euid, Process.egid
      target_uid = Etc.getpwnam(user).uid if user
      target_gid = Etc.getgrnam(group).gid if group

      if uid != target_uid || gid != target_gid
        Process.initgroups(user, target_gid)
        Process::GID.change_privilege(target_gid)
        Process::UID.change_privilege(target_uid)
      end
    rescue Errno::EPERM => e
      STDERR.puts "Couldn't change user and group to #{user}:#{group}: #{e}."
    end
    
    private
      def remove_pid_file
        File.delete(@pid_file) if @pid_file && File.exists?(@pid_file)
      end

      def write_pid_file
        FileUtils.mkdir_p File.dirname(@pid_file)
        open(@pid_file,"w") { |f| f.write(Process.pid) }
      end
  end
end