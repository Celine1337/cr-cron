# cr-cron - cron next-run calculator. Pure Crystal, no dependencies.
#
# usage: cr-cron "<5-field cron expr>" [count] [base-time]
#   fields: minute hour day-of-month month day-of-week
#   syntax: *  a  a-b  a,b,c  */n  a-b/n  a/n
#   dow: 0-7 (0 and 7 both mean Sunday)
#   base-time: ISO8601 UTC, e.g. 2026-11-12T10:00:00 (default: now, UTC)
# Prints the next `count` matching times (default 5), one per line, strictly
# after base-time. Standard cron rule: when BOTH day-of-month and day-of-week
# are restricted (do not start with '*'), a day matches if EITHER matches;
# otherwise all fields are ANDed.

class CronError < Exception
end

# One parsed cron field: the set of allowed values plus whether the raw
# field was a "star" field (starts with '*'), which matters for the
# day-of-month / day-of-week OR rule.
struct Field
  getter values : Set(Int32)
  getter? star : Bool

  def initialize(@values : Set(Int32), @star : Bool)
  end

  def matches?(v : Int32) : Bool
    @values.includes?(v)
  end
end

def parse_int(s : String) : Int32
  n = s.to_i?
  raise CronError.new("bad number '#{s}'") if n.nil? || s.empty? || !s.each_char.all?(&.ascii_number?)
  n
end

# Parse one cron field into a Field. `lo`/`hi` are the inclusive bounds for
# the field; `dow` enables the 7 -> 0 (Sunday) normalization.
def parse_field(spec : String, lo : Int32, hi : Int32, name : String, dow = false) : Field
  raise CronError.new("empty #{name} field") if spec.empty?
  star = spec.starts_with?('*')
  values = Set(Int32).new
  spec.split(',').each do |part|
    raise CronError.new("empty item in #{name} field") if part.empty?
    step = 1
    stepped = false
    if part.includes?('/')
      pieces = part.split('/')
      raise CronError.new("bad step in #{name} field: '#{part}'") unless pieces.size == 2
      step = parse_int(pieces[1])
      raise CronError.new("step must be >= 1 in #{name} field: '#{part}'") if step < 1
      stepped = true
      part = pieces[0]
    end
    if part == "*"
      a, b = lo, hi
    elsif part.includes?('-')
      ab = part.split('-')
      raise CronError.new("bad range in #{name} field: '#{part}'") unless ab.size == 2
      a = parse_int(ab[0])
      b = parse_int(ab[1])
      raise CronError.new("range start > end in #{name} field: '#{part}'") if a > b
    else
      a = parse_int(part)
      b = stepped ? hi : a
    end
    raise CronError.new("value out of range (#{lo}-#{hi}) in #{name} field: '#{part}'") if a < lo || b > hi
    v = a
    while v <= b
      values << (dow && v == 7 ? 0 : v)
      v += step
    end
  end
  Field.new(values, star)
end

struct Schedule
  getter minute : Field
  getter hour : Field
  getter dom : Field
  getter month : Field
  getter dow : Field

  def initialize(expr : String)
    fields = expr.split(' ', remove_empty: true)
    raise CronError.new("expected 5 fields, got #{fields.size}") unless fields.size == 5
    @minute = parse_field(fields[0], 0, 59, "minute")
    @hour = parse_field(fields[1], 0, 23, "hour")
    @dom = parse_field(fields[2], 1, 31, "day-of-month")
    @month = parse_field(fields[3], 1, 12, "month")
    @dow = parse_field(fields[4], 0, 7, "day-of-week", dow: true)
  end

  # Standard cron day rule: OR when both dom and dow are restricted, else AND.
  # Crystal's DayOfWeek is ISO-numbered (Monday=1 .. Sunday=7); % 7 maps it
  # to cron numbering (Sunday=0 .. Saturday=6).
  def day_matches?(t : Time) : Bool
    dom_ok = @dom.matches?(t.day)
    dow_ok = @dow.matches?(t.day_of_week.value % 7)
    if @dom.star? && @dow.star?
      true
    elsif @dom.star?
      dow_ok
    elsif @dow.star?
      dom_ok
    else
      dom_ok || dow_ok
    end
  end

  # Print the next `count` run times strictly after `base`, searching at most
  # 4 years ahead (1461 days, enough for any leap-year schedule).
  def run(base : Time, count : Int32) : Int32
    t = Time.utc(base.year, base.month, base.day, base.hour, base.minute) + 1.minute
    limit = base + 1461.days
    found = 0
    while found < count && t <= limit
      unless @month.matches?(t.month)
        t = t.month == 12 ? Time.utc(t.year + 1, 1, 1) : Time.utc(t.year, t.month + 1, 1)
        next
      end
      unless day_matches?(t)
        t = Time.utc(t.year, t.month, t.day) + 1.day
        next
      end
      unless @hour.matches?(t.hour)
        t = Time.utc(t.year, t.month, t.day, t.hour) + 1.hour
        next
      end
      unless @minute.matches?(t.minute)
        t += 1.minute
        next
      end
      puts t.to_s("%Y-%m-%dT%H:%M:%SZ")
      found += 1
      t += 1.minute
    end
    found
  end
end

def usage
  STDERR.puts <<-USAGE
  usage:
    cr-cron "<cron expr>" [count] [base-time]
      cron expr : 5 fields "minute hour day-of-month month day-of-week"
                  supports * a a-b a,b,c */n a-b/n a/n ; dow 0-7 (0,7 = Sunday)
      count     : how many upcoming run times to print (default 5)
      base-time : ISO8601 UTC like 2026-11-12T10:00:00 (default: now)
  USAGE
  exit 2
end

def parse_base(s : String) : Time
  m = s.match(/\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z?\z/)
  raise ArgumentError.new("bad base-time '#{s}' (want YYYY-MM-DDTHH:MM:SS)") unless m
  Time.utc(m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, m[6].to_i)
rescue ex : ArgumentError
  raise ArgumentError.new("bad base-time '#{s}': #{ex.message}")
end

begin
  usage if ARGV.empty? || ARGV.size > 3
  expr = ARGV[0]
  count = 5
  if ARGV.size >= 2
    count = ARGV[1].to_i?
    if count.nil? || count < 1 || !ARGV[1].each_char.all?(&.ascii_number?)
      STDERR.puts "cr-cron: bad count '#{ARGV[1]}' (want a positive integer)"
      usage
    end
  end
  base = ARGV.size >= 3 ? parse_base(ARGV[2]) : Time.utc
  schedule = Schedule.new(expr)
  found = schedule.run(base, count)
  if found < count
    STDERR.puts "cr-cron: only #{found} matching time(s) within 4 years of base (asked for #{count})"
    exit 1
  end
rescue ex : CronError
  STDERR.puts "cr-cron: invalid cron expression: #{ex.message}"
  exit 1
rescue ex : ArgumentError
  STDERR.puts "cr-cron: #{ex.message}"
  exit 2
end