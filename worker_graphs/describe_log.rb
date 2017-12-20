#!/usr/bin/env ruby

require "set"
require "optparse" # rb
require "zlib"     # rb
ZIP_READER=Zlib::GzipReader # rb

class DescribeLog
  def initialize(options = {})
    @verbose = true
    #              (severity),   (date)    (time)    .(ms)     #(pid)   :(thread_id)    (severity)   (progname): (msg)
    @regex = /^\[-*\] ([A-Z]), \[([-0-9]*)T([0-9:]*)\.([0-9]*) #([0-9]*):([a-z0-9]*)\] +([A-Z]{0,5}) -- ([^:]*): (.*)$/
    @pid_id = 5
    @message_id = 9
    @sort = options[:sort]
    @details = options[:details]
    @max = options[:max]
    @worker_types = /#{options[:worker_types]}/ if options[:worker_types]
    @messages = options[:messages]
  end

  # shell
  def run(files)
    keep = []
    pids = {} # of String => Hash of (String => Array(String) | String)
    parse_files(files, pids, keep)

    all_processes = (pids.values + keep)

    if @sort == :pid # default mode
      puts "# pid count name start end"
      all_processes.sort_by { |pa| pa[:min_time] || "" }.each do |pid_attrs|
        worker_name = pid_attrs[:name] || "UNKNOWN"
        case @details
        #when :name
        #when :count
        when :pid
          puts "%8s %s" % [pid_attrs[:pid], pid_attrs[:name]]
        when :details
          puts "%8s [%7d] %s -- %s %s" % [pid_attrs[:pid], pid_attrs[:line_count], pid_attrs[:min_time], pid_attrs[:max_time], worker_name]
          if @messages
            puts "MM"
            pid_attrs[:messages].sort_by {|_, count| -count }.each do |message, count|
              puts "    %5d %s" % [count, message]
            end
          end
        end
      end
    else
      all_processes.group_by { |pid_attrs| pid_attrs[:name] || "UNKNOWN"}.sort_by { |worker_name, _| worker_name || "UNKNOWN"}.each do |worker_name, pid_attrs|
        worker_name ||= "UNKNOWN"
        case @details
        when :name
          puts "#{worker_name}"
        when :count
          puts "#{worker_name} #{pid_attrs.size}"
        when :pid
          puts "#{worker_name} #{pid_attrs.map { |pa| pa[:pid]}.join " "}"
        when :details
          puts "#{worker_name} (#{pid_attrs.size})"

          pid_attrs = pid_attrs.sort_by { |pa| pa[:min_time] || "" }
          if @max
            lots = "  %8s" % ["..."] if pid_attrs.size > @max
            pid_attrs = pid_attrs[0..@max]
          end
          pid_attrs.each do |pid_attrs|
            # pid, linecount, min time, max time
            puts "  %8s [%7d] %s -- %s" % [pid_attrs[:pid], pid_attrs[:line_count], pid_attrs[:min_time], pid_attrs[:max_time]]
            if @messages
            pid_attrs[:messages].sort_by {|_, count| -count }.each do |message, count|
                puts "  %8s [%7d] %s" % ["", count, message]
              end
            end
          end
          puts lots if lots
        end
      end
    end
  end

  # go through filenames and parse each one
  # handles ziping and the like
  def parse_files(filenames, pids, keep)
    filenames.each do |filename|
      if filename == "-"
        # puts "#  stdin:" if @verbose
        parse_file(STDIN, pids, keep)
      else
        puts "#  #{filename}:" if @verbose
        file_io = File.extname(filename) == ".gz" ? ZIP_READER : File
        file_io.open(filename) { |f| parse_file(f, pids, keep) }
      end
    end
  end

  def parse_file(stream, pids, keep)
    count = 0
    ignore = Set.new
    stream.each_line do |line|
      if (m=@regex.match(line))
        current_pid = m[@pid_id]
        message = m[@message_id]

        if !ignore.include?(current_pid)
          current ||= pids[current_pid] ||= {:line_count => 0, :pid => current_pid, :messages => {}}

          timestamp = "#{m[2]}T#{m[3]}"
          current[:min_time] = timestamp if (current[:min_time] || "9") > timestamp # "9" > "2017-..."
          current[:max_time] = timestamp if (current[:max_time] || "0") < timestamp # "0" < "2017-..."
          current[:line_count] += 1

          if current[:name].nil?
            if message =~ /^MIQ\((MiqServer)/
              current[:name] = $1
            elsif message =~ /^MIQ\(([^ ]*)::Runner/
              current[:name] = $1
            # TODO: feedback on whether we're missing something
            end
            # is this a worker we want to ignore?
            ignore << current_pid if @worker_types && current[:name] && current[:name] !~ @worker_types
          end
          # may want queue name as well ala Ident: \[([^,]*)\]
          if @messages && (message =~ /::Runner#get_message_via_drb.*Command: \[([^,]*)\]/)
            current[:messages][$1] = (current[:messages][$1] || 0) + 1
          end
        end

        # removing pid from the active list when it is going away
        # would like a better way to know it was going away
        # this is to support recycled pids
        if message.include?("Worker exiting")
          ignore.delete(current_pid)
          current = pids.delete(current_pid)
          keep << current if current
        end
      end
    end
  end
end

options = {:sort => :pid, :details => :details}

OptionParser.new do |opt|
  opt.banner = "Usage: describe_log.rb"
  opt.separator ""
  opt.separator "Describe the contents of a log"
  opt.separator ""
  opt.separator "Options"
  opt.on("-h", "--help",         "Show this help")           { puts opt ; exit }
  opt.on("-g", "--group",        "Group by worker type")     { options[:sort] = :worker }
  opt.on("-n", "--name",         "Display worker name")      { options[:sort] = :worker ; options[:details] = :name }
  opt.on("-c", "--count",        "Display worker counts")    { options[:sort] = :worker ; options[:details] = :count }
  opt.on("-p", "--pids",         "Display pids")             { options[:details] = :pid }
  opt.on("-d", "--details",      "Display worker details")   { options[:details] = :details }
  opt.on("-m", "--messages",     "Display message details")  { options[:messages] = true }
  opt.on("--worker_types REGEX", "Worker types to keep")     { |v| options[:worker_types] = v }
  opt.on("--max MAX",            "Max pids per worker type") { |v| options[:max] = v.to_i }
  opt.parse!
end

filenames = ARGV if ARGV
dl = DescribeLog.new(options)
worker_types = dl.run(filenames)
