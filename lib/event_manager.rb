require 'csv'
require 'google/apis/civicinfo_v2'
require 'erb'
require 'date'

module EventManager
  CIVIC_INFO_KEY = 'AIzaSyClRzDqDh5MsXwnCWi0kOiiBivP6JsSyBw'

  class << self
    def run
      puts 'EventManager initialized.'
      contents = load_csv('event_attendees.csv')
      template_letter = File.read('form_letter.erb')
      erb_template = ERB.new(template_letter)

      process_attendees(contents, erb_template)
      analyze_registration_times(contents)
    end

    private

    def load_csv(filename)
      CSV.open(filename, headers: true, header_converters: :symbol)
    end

    def process_attendees(contents, erb_template)
      contents.each do |row|
        id = row[0]
        name = row[:first_name]
        zipcode = clean_zipcode(row[:zipcode])
        phone_number = clean_phone_number(row[:homephone])
        legislators = legislators_by_zipcode(zipcode)

        form_letter = erb_template.result(binding)
        save_thank_you_letter(id, form_letter)
      end
    end

    def analyze_registration_times(contents)
      contents.rewind
      hour_counts = count_registrations_by_hour(contents)
      peak_hours = find_peak_times(hour_counts)

      contents.rewind
      day_counts = count_registrations_by_day(contents)
      peak_days = find_peak_times(day_counts)

      print_registration_statistics(hour_counts, peak_hours, day_counts, peak_days)
    end

    def clean_zipcode(zipcode)
      zipcode.to_s.rjust(5, '0')[0..4]
    end

    def clean_phone_number(phone_number)
      digits = phone_number.to_s.gsub(/\D/, '')
      case digits.length
      when 10 then digits
      when 11 then digits.start_with?('1') ? digits[1..] : 'Invalid phone number'
      else 'Invalid phone number'
      end
    end

    def legislators_by_zipcode(zip)
      civic_info = Google::Apis::CivicinfoV2::CivicInfoService.new
      civic_info.key = CIVIC_INFO_KEY

      begin
        civic_info.representative_info_by_address(
          address: zip,
          levels: 'country',
          roles: %w[legislatorUpperBody legislatorLowerBody]
        ).officials
      rescue StandardError
        'You can find your representatives by visiting www.commoncause.org/take-action/find-elected-officials'
      end
    end

    def save_thank_you_letter(id, form_letter)
      Dir.mkdir('output') unless Dir.exist?('output')
      filename = "output/thanks_#{id}.html"
      File.open(filename, 'w') { |file| file.puts form_letter }
    end

    def extract_datetime(date_string)
      datetime = DateTime.strptime(date_string, '%m/%d/%y %H:%M')
      [datetime.hour, datetime.wday]
    end

    def count_registrations_by_hour(contents)
      count_registrations(contents) { |row| extract_datetime(row[:regdate])[0] }
    end

    def count_registrations_by_day(contents)
      count_registrations(contents) { |row| extract_datetime(row[:regdate])[1] }
    end

    def count_registrations(contents)
      contents.each_with_object(Hash.new(0)) do |row, counts|
        key = yield(row)
        counts[key] += 1
      end
    end

    def find_peak_times(counts)
      max_count = counts.values.max
      counts.select { |_, count| count == max_count }.keys
    end

    def day_name(day_number)
      Date::DAYNAMES[day_number]
    end

    def print_registration_statistics(hour_counts, peak_hours, day_counts, peak_days)
      puts "\nRegistration hour statistics:"
      hour_counts.sort.each { |hour, count| puts "Hour #{hour}: #{count} registrations" }
      puts "\nPeak registration hour(s): #{peak_hours.join(', ')}"

      puts "\nRegistration day statistics:"
      day_counts.sort.each { |day, count| puts "#{day_name(day)}: #{count} registrations" }
      puts "\nPeak registration day(s): #{peak_days.map { |day| day_name(day) }.join(', ')}"
    end
  end
end

EventManager.run
