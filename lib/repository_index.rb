# frozen_string_literal: true

# Renders the README's repository index: a table row per category listing its
# repositories in the order they appear in the data
class RepositoryIndex
  class CategorisationError < StandardError; end
  class MissingMarkersError < StandardError; end

  START_MARKER = "<!-- repository-index:start -->"
  END_MARKER = "<!-- repository-index:end -->"
  TABLE_HEADER = <<~MARKDOWN.chomp
    | category | repositories |
    | -------- | ------------ |
  MARKDOWN

  def initialize(repositories:, categories:, login:)
    @repositories = repositories.to_h do |repository|
      [full_name(repository), repository]
    end
    @categories = categories
    @login = login
  end

  def insert_into(readme)
    pattern = /#{Regexp.escape(START_MARKER)}.*?#{Regexp.escape(END_MARKER)}/m
    unless readme.match?(pattern)
      raise MissingMarkersError,
            "Expected the README to contain #{START_MARKER} followed by " \
            "#{END_MARKER}"
    end

    readme.sub(pattern) do
      "#{START_MARKER}\n\n#{to_markdown}\n\n#{END_MARKER}"
    end
  end

  def to_markdown
    check_categorisation

    rows = @categories.map do |category, full_names|
      category_row(category, full_names)
    end
    [TABLE_HEADER, *rows].join("\n")
  end

  private

  def check_categorisation
    categorised = @categories.values.compact.flatten
    empty_categories = @categories.select do |_category, full_names|
      full_names.nil? || full_names.empty?
    end

    problems = {
      "Categories with no repositories" => empty_categories.keys,
      "Repositories in more than one category" =>
        categorised.tally.select { |_name, count| count > 1 }.keys,
      "Categorised repositories missing from the data" =>
        categorised - @repositories.keys,
      "Uncategorised repositories" => @repositories.keys - categorised,
    }.reject { |_problem, names| names.empty? }
    return if problems.empty?

    messages = problems.map do |problem, names|
      "#{problem}: #{names.join(', ')}"
    end
    raise CategorisationError, messages.join("\n")
  end

  def category_row(category, full_names)
    repositories = @repositories.filter_map do |full_name, repository|
      repository if full_names.include?(full_name)
    end
    owners = repositories.map { |repository| repository.fetch("org") }.uniq
    shared_owner = owners.first if owners.one?

    owner_prefix = shared_owner ? "#{shared_owner}/ → " : ""
    links = repositories.map do |repository|
      link_text =
        shared_owner ? repository.fetch("name") : full_name(repository)
      "[#{link_text}](#{link_url(repository)})"
    end

    "| #{escape_pipes(category)} | #{owner_prefix}#{links.join(', ')} |"
  end

  def link_url(repository)
    url = repository.fetch("url")
    return url if repository.fetch("org") == @login

    "#{url}/commits?author=#{@login}"
  end

  def escape_pipes(text)
    text.gsub("|") { "\\|" }
  end

  def full_name(repository)
    "#{repository.fetch('org')}/#{repository.fetch('name')}"
  end
end
