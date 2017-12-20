#!/usr/bin/env ruby

require "optparse" # rb
require "zlib"     # rb
ZIP_READER=Zlib::GzipReader # rb

# require "option_parser" # cry
# require "gzip"          # cry
# ZIP_READER=Gzip::Reader       # cry
# cry: include? -> includes

class SplitLogs
  def initialize
    # base output name for log files
    @log = nil
    # base output name for data files
    @data = nil
    # files to parse
    @filenames = [] #of String
    # pids to limit processing
    @pids      = [] #of String

    #              (severity),   (date)    (time)    .(ms)     #(pid)   :(thread_id)    (severity)   (progname): (msg)
    @regex = /^\[-*\] ([A-Z]), \[([-0-9]*)T([0-9:]*)\.([0-9]*) #([0-9]*):([a-z0-9]*)\] +([A-Z]{0,5}) -- ([^:]*): (.*)$/
    @keep  = nil
    # capture id in @regex for the pid (for use in the filename)
    @pid_id = 5
    # continue capturing short log lines (without date/pid prefix)
    # this should be true for simple splitting
    @keep_short_log_lines = true

    # derive base and log filenames based upon first arg
    @derive = false
  end

  def run
    pid_files  = {} #of String => File
    data_files = {} #of String => File

    parse_args
    validate_args

    parse_files(@filenames, pid_files, data_files)
  ensure
    pid_files.each { |_n, f| f.close } if pid_files
    data_files.each { |_n, f| f.close } if data_files
  end

  def parse_args
    OptionParser.new do |opt|
      opt.banner = "Usage: split_logs.rb --name worker_name [log_file_names]"
      opt.separator ""
      opt.separator "Split a log file into multiple log files (by pid)"
      opt.separator ""
      opt.separator "Options"
      opt.on("-p", "--pid=PID", "comma separated list of pids to include in output") { |v| @pids += v.split(",") if v }
      opt.on("-l BASE", "--log=BASE", "basename for log output") { |v| @log = v if v }
      opt.on("--regex REGEX", "Regular Expression to use to determine pid") { |v| @regex = /#{v}/ }
      opt.on("--id REGEX_ID", "capture id for the PID in the regular expression (defaults to 1)") { |v| @pid_id = v.to_i }
      opt.on("--keep REGEX", "Regular Expression of lines to keep") { |v| @keep = /#{v}/ }
      opt.on("--no-follow", "Include following lines that don't have pids in previous file") { @keep_short_log_lines = false }
      opt.on("-d BASE", "--data=BASE", "basename for data output") { |v| @data = v if v }
      opt.on("--dl", "default data and log") { |v| @derive = v if v}
      opt.on("-h", "--help", "Show this help") { puts opt ; exit }
      opt.parse!
    end

    @filenames = ARGV if ARGV
    if @derive
      dirname = File.dirname(@filenames.first)
      @log  = "#{dirname}/evm.log"
      @data = "#{dirname}/evm.data"
    end
  end

  def validate_args
    if @filenames.empty?
      puts "No filenames specified"
      exit 1
    end

    if @log.nil? && @data.nil?
      puts "Need basename for log and/or data output"
      exit 1
    end

    if (tmp = @log) && !tmp.include?("%s")
      @log = "#{@log}_pid_%s"
    end

    if (tmp = @data) && !tmp.include?("%s")
      @data = "#{@data}_pid_%s"
    end
  end

  # go through filenames and parse each one
  # handles ziping and the like
  def parse_files(filenames, pid_files, data_files)
    filenames.each do |filename|
      skip = 0
      if filename == "-"
        puts "  stdin:"
        skip = parse_file(STDIN, pid_files, data_files)
      else
        puts "  #{filename}:"
        file_io = File.extname(filename) == ".gz" ? ZIP_READER : File
        skip = file_io.open(filename) { |f| parse_file(f, pid_files, data_files) }
      end
      # NOTE: sometimes the first line of a log file is a comment when the log file was created
      # may want to have skip > 1
      puts "X #{filename == "-" ? "stdin" : filename}: skipped #{skip} lines" if skip > 0
    end
  end

  # @return [Integer] the number of lines skipped
  def parse_file(file, pid_files, data_files)
    skip = 0 # number of input lines we skipped
    output_pid = nil
    output_data = nil

    file.each_line do |line|
      if (m=@regex.match(line))
        current_pid = m[@pid_id]
        if (@pids.empty? || @pids.include?(current_pid)) && # have pid (if we are limiting pids)
           (@keep.nil?   || (line =~ @keep))              && # line checks out (if we have extra regex)
           (m            || @keep_short_log_lines)           # matches common log format, or we include short lines
          output_pid  = select_output(current_pid, @log, pid_files)
          output_data = select_output(current_pid, @data, data_files)
        else
          output_pid = output_data = nil
        end
      end

      if (output_data.nil? && output_pid.nil?) # both output types said no thank you
        skip += 1
      else
        # puts line if output_pid
        output_pid.puts line if output_pid
        if m && output_data
          output_data(line, m, output_data)
        end
      end
    end
    skip
  end

  # private

  # factory method
  def select_output(current_pid, base, cache)
    return unless base
    cache[current_pid] ||= begin
      new_filename = base % current_pid
      puts "# #{new_filename}"
      File.open(new_filename, "a")
    end
  end

  def parse_regex(line, regex)
    rslt = regex.match(line)
    rslt[1] if rslt
  end

  def output_data(line, m, output_data)
    # TODO: handle other expressions
    s1, dt, tm, ms, pid, thd, sev, progname, msg = m.captures
    return unless msg
    command    = parse_regex(msg, /Command: \[([^\]]*)\]/)
    # time                                               # 1
    pss        = parse_regex(msg, /PSS: \[([^\]]*)\]/)                 # 2
    rss        = parse_regex(msg, /RSS: \[([^\]]*)\]/)                 # 3
    live       = parse_regex(msg, /Live Objects: \[([^\]]*)\]/)        # 4
    old        = parse_regex(msg, /Old Objects: \[([^\]]*)\]/)         # 5
    heap_all   = parse_regex(msg, /All Heap Slots: \[([^\]]*)\]/)      # 6
    heap_live  = parse_regex(msg, /Live Heap Slots: \[([^\]]*)\]/)     # 7
    gc         = parse_regex(msg, /GC: \[([^\]]*)\]/)                  # 8
    other      = parse_regex(msg, /::Runner\) ([^,]*),/) # 9

    return unless rss
    # gnuplot doesn't like usec
    # output_data = STDOUT # HACK
    output_data << "#{dt}T#{tm}"             \
                << " " << pss                \
                << " " << rss                \
                << " " << live               \
                << " " << old                \
                << " " << heap_all           \
                << " " << heap_live          \
                << " " << gc                 \
                << " ### " << (command || "") \
                << " " << other << "\n"
  end
end

SplitLogs.new.run
