# frozen_string_literal: true

require "date"

# Counts a GitHub user's commits to each repository, from the commit
# contributions GitHub records on their profile
class CommitsByRepository
  class TooManyRepositoriesError < StandardError; end

  YEARS_QUERY = <<~GRAPHQL
    query($login: String!) {
      user(login: $login) {
        contributionsCollection { contributionYears }
      }
    }
  GRAPHQL

  # `maxRepositories` can't exceed 100, so windows with more are split
  WINDOW_QUERY = <<~GRAPHQL
    query($login: String!, $from: DateTime!, $to: DateTime!) {
      user(login: $login) {
        contributionsCollection(from: $from, to: $to) {
          totalRepositoriesWithContributedCommits
          commitContributionsByRepository(maxRepositories: 100) {
            repository { name owner { login } url }
            contributions { totalCount }
          }
        }
      }
    }
  GRAPHQL

  def initialize(login:, client:, today: Date.today)
    @login = login
    @client = client
    @today = today
  end

  def repositories
    totals = {}

    each_month do |first_day, last_day|
      year = first_day.year.to_s
      month = first_day.strftime("%Y-%m")

      commit_counts(first_day, last_day).each do |repository, commit_count|
        total = totals[repository.fetch("url")] ||= {
          "org" => repository.dig("owner", "login"),
          "name" => repository.fetch("name"),
          "url" => repository.fetch("url"),
          "commit_count" => 0,
          "commit_counts_by_year" => {},
          "first_commit_month" => month,
          "latest_commit_month" => month,
        }
        counts_by_year = total["commit_counts_by_year"]
        total["commit_count"] += commit_count
        counts_by_year[year] = counts_by_year.fetch(year, 0) + commit_count
        total["latest_commit_month"] = month
      end
    end

    sort_by_recent_commits(totals.values)
  end

  private

  def each_month
    contribution_years.sort.each do |year|
      (1..12).each do |month|
        first_day = Date.new(year, month, 1)
        break if first_day > @today

        yield first_day, first_day.next_month - 1
      end
    end
  end

  def contribution_years
    @client.query(YEARS_QUERY, "login" => @login)
      .dig("user", "contributionsCollection", "contributionYears")
  end

  def commit_counts(first_day, last_day)
    collection = @client.query(
      WINDOW_QUERY,
      "login" => @login,
      "from" => "#{first_day.iso8601}T00:00:00Z",
      "to" => "#{last_day.iso8601}T23:59:59Z",
    ).dig("user", "contributionsCollection")
    by_repository = collection.fetch("commitContributionsByRepository")

    if collection.fetch("totalRepositoriesWithContributedCommits") <=
       by_repository.length
      return by_repository.map do |repository_contributions|
        [
          repository_contributions.fetch("repository"),
          repository_contributions.dig("contributions", "totalCount"),
        ]
      end
    end

    if first_day == last_day
      raise TooManyRepositoriesError,
            "Over 100 repositories on #{first_day.iso8601}"
    end

    midpoint = first_day + ((last_day - first_day).to_i / 2)
    commit_counts(first_day, midpoint) + commit_counts(midpoint + 1, last_day)
  end

  # Orders by commits in the latest year, then the year before, and so on
  def sort_by_recent_commits(totals)
    years = totals
      .flat_map { |total| total["commit_counts_by_year"].keys }
      .uniq.sort.reverse

    totals.sort_by do |total|
      counts_by_year = total["commit_counts_by_year"]
      [
        *years.map { |year| -counts_by_year.fetch(year, 0) },
        total["org"].downcase,
        total["name"].downcase,
      ]
    end
  end
end
