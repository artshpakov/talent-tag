class Bsp < Thor

  desc "fetch", "fetch data from remote server"
  method_option :date, aliases: "-d", desc: "Specify a date in a YYYY-MM-DD or YYYY-MM-DD:YYYY-MM-DD (for multiple dates) format"
  def fetch
    require 'open-uri'
    require 'json'
    require File.expand_path("config/environment.rb")

    started_at = Time.now
    total_entries_fetched = if options[:date] then fetch_by_date(options[:date]) else fetch_recent end
    puts "\n#{ Time.now.strftime("%d.%m.%Y %H:%M %Z") }: #{ total_entries_fetched } entries stored in #{ (Time.now - started_at).to_i } seconds\n"

    system "rake ts:index > /dev/null" unless total_entries_fetched.zero?
    TalentTag::Application::Redis.set "stats:last_fetch_time", Time.now
  end


  private

  def endpoint_url
    "http://api.brandspotter.ru/v2/clients/1071/mentions.json?api_key=ubx260cagzy287shpdjk935ntr2jl0cr"
  end

  def fetch_recent
    request_and_parse endpoint_url
  end

  def fetch_by_date dates
    dates = dates.split(":")
    (dates.first..dates.last).reduce(0) do |total_sum, date|
      puts "\nfetching data for #{ date }\n"
      date  = Date.strptime date
      url   = "#{ endpoint_url }&?filters[created_at_gte]=#{ date.strftime("%Y-%m-%d") }&filters[created_at_lt]=#{ (date+1).strftime("%Y-%m-%d") }"

      p url

      pages = JSON.parse(open(url).read)['meta']['pagination']['total_pages']
      total_sum + (0..pages-1).reduce(0) do |sum, page|
        sum + request_and_parse("#{ url }&page=#{ page }")
      end
    end
  end


  def request_and_parse url
    saved_entries = 0
    data          = JSON.parse open(url).read

    data['items'].each { |item| Source.create item['platform'] }

    data['items'].map do |entry|

      if source = (entry['platform']['id'] rescue nil) && Source.find_by(id: entry['platform']['id'])

        entry['body'].gsub!(/<\/?[^>]*>/, "")
        entry['body'].gsub!(/#linkedincorpus/, '').try :'strip!'

        entry = source.entries.new \
          id: entry['id'],
          body: entry['body'],
          url: entry['url'],
          author: entry['author'],
          created_at: entry['created_at'],
          fetched_at: Time.now

        if identity = entry.identity
          user = identity.user
          profile = user.profile || {}
          profile['tags'] = ((profile['tags'] || []) + entry.hashtags).uniq
          user.profile_will_change!
          user.save
        end

        if entry.valid? && entry.save
          saved_entries += 1
          print '.'
        end
      end
    end

    saved_entries
  end

end
