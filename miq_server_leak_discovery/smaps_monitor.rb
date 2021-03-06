class SmapsWatcher
  MAP_LINE_REGEXP      = /^[\-0-9a-f]+\s[\-a-z]{4}\s\d{8}\s[a-z0-9]{2}:[a-z0-9]{2}\s\d+\s+(.*)$/
  SIZE_SMAPS_REGEXP    = /^Size:\s+?(\d+)/
  PSS_SMAPS_REGEXP     = /^Pss:\s+?(\d+)/
  RSS_SMAPS_REGEXP     = /^Rss:\s+?(\d+)/
  SWAP_SMAPS_REGEXP    = /^Swap:\s+?(\d+)/
  USS_SMAPS_REGEXP     = /^Private_(Clean|Dirty):\s+?(\d+)/
  MIQSERVER_LOG_REGEXP = /^\[----\] [A-Z], (\[[-0-9]*T[0-9:]*\.[0-9]*) #[0-9]*:[a-z0-9]*\] +([A-Z]{0,5} -- [^:]*: MIQ\(MiqServer.*)$/
  def self.smaps_diff(pid)
    filename             = "/proc/#{pid}/smaps"
    @previous_smaps    ||= {}
    current_smaps        = {}
    current_smaps_lineno = 0
    lineno = 0

    # Prefer slurping up the entire file here since this is a psuedo file.
    # This should get garbage collected anyway, so should be fine.
    File.read("/proc/#{pid}/smaps").each_line do |line|
      lineno += 1
      # puts line
      case line
      when MAP_LINE_REGEXP
        current_smaps_lineno  = lineno
        current_smaps[lineno] = {:loc => Regexp.last_match[1].to_s}
      when SIZE_SMAPS_REGEXP
        current_smaps[current_smaps_lineno][:size]  = Regexp.last_match[1].to_i
      when RSS_SMAPS_REGEXP
        current_smaps[current_smaps_lineno][:rss]   = Regexp.last_match[1].to_i
      when PSS_SMAPS_REGEXP
        current_smaps[current_smaps_lineno][:pss]   = Regexp.last_match[1].to_i
      when SWAP_SMAPS_REGEXP
        current_smaps[current_smaps_lineno][:swap]  = Regexp.last_match[1].to_i
      when USS_SMAPS_REGEXP
        current_smaps[current_smaps_lineno][:uss] ||= 0
        current_smaps[current_smaps_lineno][:uss]  += Regexp.last_match[1].to_i
      end
    end

    # Diff current_smaps and previous_smaps
    diff = {}
    current_smaps.each do |lnum, map|
      map.each do |key, val|
        if current_smaps[lnum][key] != @previous_smaps[lnum][key]
          diff[lnum] = {:old => @previous_smaps[lnum], :new => current_smaps[lnum]}
          break
        end
      end
    end unless @previous_smaps.keys.empty?

    @previous_smaps = current_smaps

    # Print results
    if diff.keys.empty?
      "NO Difference detected in #{filename}"
    else
      "SMAPS Difference detected in #{filename}\n".tap do |msg|
        max_lineno = diff.keys.max.to_s.length
        diff.each do |lnum,diff|
          msg << "#{lnum.to_s.ljust(max_lineno)} => old: #{diff[:old].inspect}\n"
          msg <<  "#{' '.to_s.ljust(max_lineno)}    new: #{diff[:new].inspect}\n"
        end

        log_line_count = 0
        msg << "\n\n#{Time.now}\n".tap do |log_lines|
          Elif.foreach("/var/www/miq/vmdb/log/evm.log") do |line|
            if line.match MIQSERVER_LOG_REGEXP
              log_lines << Regexp.last_match[1]
              log_lines << "] "
              log_lines << Regexp.last_match[2]
              log_lines << "\n"
              log_line_count += 1
              break if log_line_count >= 5
            end
          end
        end
      end
    end
  end
end

# Portions from `Elif` lifted from https://github.com/juliancheal/elif
#
# = License Terms
#
# Distributed under the user's choice of the GPL[http://www.gnu.org/copyleft/gpl.html] (see COPYING for details) or the
# {Ruby software license}[http://www.ruby-lang.org/en/LICENSE.txt] by
# James Edward Gray II.
#
# Please email James[mailto:james@grayproductions.net] with any questions.
#
class Elif
  MAX_READ_SIZE = 1 << 10

  def self.foreach(name, sep_string = $/)
    open(name) do |file|
      while line = file.gets(sep_string)
        yield line
      end
    end
  end

  def self.open(*args)
    file = new(*args)
    if block_given?
      begin
        yield file
      ensure
        file.close
      end
    else
      file
    end
  end

  def initialize(*args)
    # Delegate to File::new and move to the end of the file.
    @file = File.new(*args)
    @file.seek(0, IO::SEEK_END)

    # Record where we are.
    @current_pos = @file.pos

    # Get the size of the next of the first read, the dangling bit of the file.
    @read_size = @file.pos % MAX_READ_SIZE
    @read_size = MAX_READ_SIZE if @read_size.zero?

    # A buffer to hold lines read, but not yet returned.
    @line_buffer = Array.new
  end

  def gets(sep_string = $/)
    #
    # If we have more than one line in the buffer or we have reached the
    # beginning of the file, send the last line in the buffer to the caller.
    # (This may be +nil+, if the buffer has been exhausted.)
    #
    return @line_buffer.pop if @line_buffer.size > 2 or @current_pos.zero?

    #
    # If we made it this far, we need to read more data to try and find the
    # beginning of a line or the beginning of the file.  Move the file pointer
    # back a step, to give us new bytes to read.
    #
    @current_pos -= @read_size
    @file.seek(@current_pos, IO::SEEK_SET)

    #
    # Read more bytes and prepend them to the first (likely partial) line in the
    # buffer.
    #
    @line_buffer[0] = "#{@file.read(@read_size)}#{@line_buffer[0]}"
    @read_size      = MAX_READ_SIZE  # Set a size for the next read.

    #
    # Divide the first line of the buffer based on +sep_string+ and #flatten!
    # those new lines into the buffer.
    #
    @line_buffer[0] = @line_buffer[0].scan(/.*?#{Regexp.escape(sep_string)}|.+/)
    @line_buffer.flatten!

    # We have move data now, so try again to read a line...
    gets(sep_string)
  end

  def close
    @file.close
  end
end


loop do
  puts SmapsWatcher.smaps_diff ARGV[0].to_i
  sleep 10
end
