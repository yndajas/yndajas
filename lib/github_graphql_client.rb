# frozen_string_literal: true

require "json"
require "net/http"

class GitHubGraphQLClient
  ENDPOINT = URI("https://api.github.com/graphql")

  def initialize(token:)
    @token = token
  end

  def query(query, variables)
    request = Net::HTTP::Post.new(ENDPOINT)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate("query" => query, "variables" => variables)

    response = Net::HTTP.start(
      ENDPOINT.host,
      ENDPOINT.port,
      use_ssl: true,
    ) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise "GitHub API returned #{response.code}: #{response.body}"
    end

    body = JSON.parse(response.body)
    if body["errors"]
      raise "GitHub API returned errors: #{body.fetch('errors')}"
    end

    body.fetch("data")
  end
end
