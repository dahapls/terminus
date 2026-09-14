#! /usr/bin/env ruby
# frozen_string_literal: true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "icalendar", "~> 2.10"
  gem "icalendar-recurrence", "~> 1.1"
  gem "tzinfo", "~> 2.0"
end

require "json"
require "net/http"
require "uri"
require "date"
require "fileutils"
require "tzinfo"

ICAL_URLS = ENV.fetch("CALENDAR_URL").split(",").map(&:strip).reject(&:empty?)
OUTPUT_PATH = ENV.fetch("CALENDAR_OUTPUT", "public/uploads/calendar.json")
WEEK_START = (ENV["WEEK_START"] || "monday").downcase
TZ = TZInfo::Timezone.get(ENV["CALENDAR_TIMEZONE"] || "UTC")
TITLE_LENGTH = (ENV["CALENDAR_TITLE_LENGTH"] || 22).to_i
CALENDAR_LABEL_LENGTH = (ENV["CALENDAR_LABEL_LENGTH"] || 18).to_i
EVENTS_PER_DAY = (ENV["CALENDAR_EVENTS_PER_DAY"] || 5).to_i

def fetch_ics url
  uri = URI(url.sub(%r{^webcal://}, "https://"))
  Net::HTTP.get(uri).force_encoding(Encoding::UTF_8)
end

def calendar_name calendar, fallback
  name = Array(calendar.custom_property("x_wr_calname")).first.to_s.strip
  name.empty? ? fallback : name
end

def to_zone time
  return time if time.is_a?(Date) && !time.is_a?(DateTime)

  t = time.is_a?(DateTime) ? time.to_time : time
  TZ.to_local(t.utc)
end

def today_in_zone
  TZ.to_local(Time.now.utc).to_date
end

def week_range start_day
  today = today_in_zone
  offset = start_day == "sunday" ? today.wday : (today.wday + 6) % 7
  monday = today - offset
  [monday, monday + 6]
end

# Recurrences are expanded with the first occurrence's fixed UTC offset, which ignores
# daylight saving changes. Reapply the event's TZID rules to the wall-clock time instead.
def rezone time, original
  return time unless time.is_a?(Time) && original.respond_to?(:ical_params)

  tzid = Array(original.ical_params["tzid"]).first
  return time unless tzid

  wall = time.getlocal(original.to_time.utc_offset)
  local = Time.utc(wall.year, wall.month, wall.day, wall.hour, wall.min, wall.sec)
  TZInfo::Timezone.get(tzid).local_to_utc(local, dst: true)
rescue TZInfo::InvalidTimezoneIdentifier, TZInfo::PeriodNotFound
  time
end

def expand_events calendars, range_start, range_end, source_name
  range_start_t = range_start.to_time
  range_end_t = (range_end + 1).to_time

  calendars.flat_map(&:events).flat_map do |event|
    event.occurrences_between(range_start_t, range_end_t).map do |occ|
      {
        event: event,
        start: rezone(occ.start_time, event.dtstart),
        finish: rezone(occ.end_time, event.dtend || event.dtstart),
        calendar: source_name
      }
    end
  rescue StandardError
    []
  end
end

def event_to_hash entry
  event = entry[:event]
  raw_start = entry[:start]
  raw_end = entry[:finish]
  all_day = raw_start.is_a?(Date) && !raw_start.is_a?(DateTime)
  start_t = to_zone(raw_start)
  end_t = to_zone(raw_end)
  all_day ||= (end_t - start_t).to_f >= 86_400

  {
    title: event.summary.to_s.strip,
    location: event.location.to_s.strip,
    calendar: entry[:calendar],
    start_iso: start_t.respond_to?(:iso8601) ? start_t.iso8601 : start_t.to_s,
    end_iso: end_t.respond_to?(:iso8601) ? end_t.iso8601 : end_t.to_s,
    date: start_t.to_date.iso8601,
    weekday: start_t.to_date.strftime("%a"),
    start_time: all_day ? nil : start_t.strftime("%H:%M"),
    all_day: all_day
  }
end

def build_week range_start, range_end, events_by_date
  today = today_in_zone
  (range_start..range_end).map do |date|
    {
      date: date.iso8601,
      weekday: date.strftime("%a"),
      day: date.strftime("%-d"),
      month: date.strftime("%b"),
      is_today: date == today,
      events: (events_by_date[date.iso8601] || []).sort_by { |e| [e[:all_day] ? 0 : 1, e[:start_time].to_s] }
    }
  end
end

range_start, range_end = week_range(WEEK_START)

successes = 0
entries = ICAL_URLS.each_with_index.flat_map do |url, idx|
  ics = fetch_ics(url)
  calendars = Icalendar::Calendar.parse(ics)
  name = calendars.first ? calendar_name(calendars.first, "Calendar #{idx + 1}") : "Calendar #{idx + 1}"
  successes += 1
  expand_events(calendars, range_start, range_end, name)
rescue StandardError => e
  warn "Skipping calendar #{idx + 1} (#{url[0, 60]}...): #{e.class}: #{e.message}"
  []
end

if successes.zero?
  warn "All calendar fetches failed; leaving existing #{OUTPUT_PATH} untouched."
  exit 1
end

events = entries.map { event_to_hash it }
events_by_date = events.group_by { it[:date] }

payload = {
  generated_at: TZ.to_local(Time.now.utc).iso8601,
  timezone: TZ.identifier,
  range_start: range_start.iso8601,
  range_end: range_end.iso8601,
  config: {
    title_length: TITLE_LENGTH,
    calendar_label_length: CALENDAR_LABEL_LENGTH,
    events_per_day: EVENTS_PER_DAY
  },
  days: build_week(range_start, range_end, events_by_date)
}

FileUtils.mkdir_p File.dirname(OUTPUT_PATH)
File.write OUTPUT_PATH, JSON.pretty_generate(payload)
puts "Wrote #{events.size} events to #{OUTPUT_PATH}"
