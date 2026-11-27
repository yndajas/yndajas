# frozen_string_literal: true

require "test_helper"
require "commits_by_repository"

# Answers contribution queries for any window from per-day commit counts,
# returning at most `max_repositories` repositories per query, like the
# `maxRepositories` argument (capped at 100) does
class FakeGitHubGraphQLClient
  attr_reader :windows_queried

  def initialize(commits_by_day:, max_repositories: 100)
    @commits_by_day = commits_by_day
    @max_repositories = max_repositories
    @windows_queried = []
  end

  def query(_query, variables)
    collection = if variables.key?("from")
      window(
        Date.parse(variables.fetch("from")),
        Date.parse(variables.fetch("to")),
      )
    else
      { "contributionYears" => @commits_by_day.keys.map(&:year).uniq }
    end

    { "user" => { "contributionsCollection" => collection } }
  end

  private

  def window(first_day, last_day)
    @windows_queried << [first_day, last_day]
    commit_counts = Hash.new(0)

    @commits_by_day.each do |day, commit_counts_on_day|
      next unless day.between?(first_day, last_day)

      commit_counts_on_day.each do |full_name, commit_count|
        commit_counts[full_name] += commit_count
      end
    end

    {
      "totalRepositoriesWithContributedCommits" => commit_counts.length,
      "commitContributionsByRepository" =>
        commit_counts.first(@max_repositories).map do |full_name, count|
          owner, name = full_name.split("/")
          {
            "repository" => {
              "name" => name,
              "owner" => { "login" => owner },
              "url" => "https://github.com/#{full_name}",
            },
            "contributions" => { "totalCount" => count },
          }
        end,
    }
  end
end

describe CommitsByRepository do
  def fetch(client, today: Date.new(2024, 12, 31))
    CommitsByRepository.new(login: "yndajas", client:, today:).repositories
  end

  def full_names(repositories)
    repositories.map do |repository|
      "#{repository['org']}/#{repository['name']}"
    end
  end

  def commit_counts_by_name(repositories)
    repositories.to_h do |repository|
      [repository["name"], repository["commit_count"]]
    end
  end

  describe "#repositories" do
    it "records each repository's org, name, and URL" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: { Date.new(2024, 1, 10) => { "alphagov/signon" => 1 } },
      )

      assert_equal(
        {
          "org" => "alphagov",
          "name" => "signon",
          "url" => "https://github.com/alphagov/signon",
        },
        fetch(client).first.slice("org", "name", "url"),
      )
    end

    it "totals each repository's commits overall and per year" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: {
          Date.new(2023, 11, 10) => { "alphagov/signon" => 4 },
          Date.new(2024, 1, 10) => { "alphagov/signon" => 2 },
          Date.new(2024, 3, 5) => { "alphagov/signon" => 3 },
        },
      )
      repository = fetch(client).first

      assert_equal 9, repository["commit_count"]
      assert_equal(
        { "2023" => 4, "2024" => 5 },
        repository["commit_counts_by_year"],
      )
    end

    it "tracks each repository's first and latest commit months" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: {
          Date.new(2024, 1, 10) => { "alphagov/signon" => 1 },
          Date.new(2024, 3, 5) => { "alphagov/signon" => 1 },
        },
      )
      repository = fetch(client).first

      assert_equal "2024-01", repository["first_commit_month"]
      assert_equal "2024-03", repository["latest_commit_month"]
    end

    it "orders by the latest year's commits, then earlier years'" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: {
          Date.new(2023, 6, 1) => {
            "yndajas/older" => 10,
            "yndajas/steady" => 1,
          },
          Date.new(2024, 6, 1) => {
            "yndajas/recent" => 2,
            "yndajas/steady" => 2,
          },
        },
      )

      assert_equal(
        ["yndajas/steady", "yndajas/recent", "yndajas/older"],
        full_names(fetch(client)),
      )
    end

    it "orders by name when commit counts match" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: {
          Date.new(2024, 1, 10) => {
            "yndajas/b" => 1,
            "yndajas/a" => 1,
            "dxw/c" => 1,
          },
        },
      )

      assert_equal(
        ["dxw/c", "yndajas/a", "yndajas/b"],
        full_names(fetch(client)),
      )
    end

    it "stops at the current month" do
      client = FakeGitHubGraphQLClient.new(
        commits_by_day: { Date.new(2024, 1, 10) => { "alphagov/signon" => 1 } },
      )

      fetch(client, today: Date.new(2024, 3, 15))

      assert_equal(
        [Date.new(2024, 3, 1), Date.new(2024, 3, 31)],
        client.windows_queried.last,
      )
    end

    describe "when a month has more repositories than one query returns" do
      it "counts every repository's commits" do
        client = FakeGitHubGraphQLClient.new(
          commits_by_day: {
            Date.new(2024, 3, 3) => { "alphagov/signon" => 2 },
            Date.new(2024, 3, 20) => { "alphagov/signon" => 3 },
            Date.new(2024, 3, 28) => { "dxw/towtruck" => 1 },
          },
          max_repositories: 1,
        )

        assert_equal(
          { "signon" => 5, "towtruck" => 1 },
          commit_counts_by_name(fetch(client)),
        )
      end
    end

    describe "when a day has more repositories than one query returns" do
      it "raises an error" do
        client = FakeGitHubGraphQLClient.new(
          commits_by_day: {
            Date.new(2024, 3, 3) => {
              "alphagov/signon" => 1,
              "dxw/towtruck" => 1,
            },
          },
          max_repositories: 1,
        )

        assert_raises(CommitsByRepository::TooManyRepositoriesError) do
          fetch(client)
        end
      end
    end
  end
end
