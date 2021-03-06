class Bsp < Thor

  require File.expand_path("config/environment.rb")


  desc "fetch", "fetch data from remote server"
  method_option :date, aliases: "-d", desc: "Specify a date in a YYYY-MM-DD or YYYY-MM-DD:YYYY-MM-DD (for multiple dates) format"
  def fetch
    require 'open-uri'
    require 'json'

    started_at = Time.now
    total_entries_fetched = if options[:date] then fetch_by_date(options[:date]) else fetch_recent end
    puts "\n#{ Time.now.strftime("%d.%m.%Y %H:%M %Z") }: #{ total_entries_fetched } entries stored in #{ (Time.now - started_at).to_i } seconds\n"

    unless total_entries_fetched.zero?
      detect_locations
      reindex!
    end
    KeyValue.set "stats:last_fetch_time", Time.now
  end

  desc "link", "associate entries with user profiles"
  def link
    Entry.find_each { |entry| entry.link_to_author! }
    reindex!
  end

  desc "location", "detect known locations in entries & profiles"
  def locations
    detect_locations
    reindex!
  end

  default_task :fetch


  private

  def endpoint_url
    "http://api.brandspotter.ru/v2/clients/1071/mentions.json?api_key=ubx260cagzy287shpdjk935ntr2jl0cr&filters[is_spam]=false&filters[has_snippet]=true"
  end

  def fetch_recent
    fetched_entries_count = request_and_parse endpoint_url
    logger.info "fetched #{fetched_entries_count} recent entries"
    fetched_entries_count
  end

  def fetch_by_date datestring
    datestring = Date.today.strftime("%Y-%m-%d") if datestring == 'today'
    dates = datestring.split(":")
    start_date = Date.strptime dates.first
    fin_date = Date.strptime dates.last

    fetched_entries_count = (start_date..fin_date).reduce(0) do |total_sum, date|
      puts "\nfetching data for #{ date }\n"
      url   = "#{ endpoint_url }&filters[created_at_gte]=#{ date.strftime("%Y-%m-%d") }&filters[created_at_lt]=#{ (date+1).strftime("%Y-%m-%d") }"
      pages = JSON.parse(open(url).read)['meta']['pagination']['total_pages']
      total_sum + (0..pages-1).reduce(0) do |sum, page|
        sum + request_and_parse("#{ url }&page=#{ page }")
      end
    end
    logger.info "fetched #{fetched_entries_count} entries for #{ datestring }"
    fetched_entries_count
  end


  def request_and_parse url
    saved_entries = 0
    begin
      data = JSON.parse open(url).read

      data['items'].each { |item| Source.create item['platform'] }

      data['items'].map do |entry_hash|

        if source = (entry_hash['platform']['id'] rescue nil) && Source.find_by(id: entry_hash['platform']['id'])
          entry_hash['body'].gsub!(/<\/?[^>]*>/, "")
          entry_hash['body'].gsub!(/#linkedincorpus/, '').try :'strip!'

          entry = source.entries.new \
            'id' => entry_hash['id'],
            'body' => entry_hash['body'],
            'url' => entry_hash['url'],
            'created_at' => entry_hash['created_at'],
            'fetched_at' => Time.now

          if entry_hash['author']
            entry['author'] = {
              'id' => entry_hash['author']['id'],
              'url' => entry_hash['author']['url'],
              'guid' => entry_hash['author']['url'],
              'name' => entry_hash['author']['name'],
              'profile' => entry_hash['author']['profile'],
            }
          end

          entry['profile_location'] = if (entry_hash['author']['profile'] rescue false)
            entry_hash['author']['profile']['city'] || entry_hash['author']['profile']['location']
          end

          if duplicate = Entry.order(:created_at).find_by(body: entry_hash['body'])
            entry['duplicate_of'] = duplicate.id
          end

          if user = entry.user
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
    rescue OpenURI::HTTPError => e
      logger.error "#{ e.message } -- #{ url }"
    end
    return saved_entries
  end


  def detect_locations
    ::Entry.update_locations
  end


  def reindex!
    system "rake ts:index > /dev/null"
  end

  def logger
    @logger ||= Logger.new("#{ Rails.root }/log/bsp.log")
  end

end
