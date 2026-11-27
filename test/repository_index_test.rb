# frozen_string_literal: true

require "test_helper"
require "repository_index"

describe RepositoryIndex do
  def repository(full_name)
    owner, name = full_name.split("/")
    {
      "org" => owner,
      "name" => name,
      "url" => "https://github.com/#{full_name}",
    }
  end

  describe "#to_markdown" do
    def assert_categorisation_error(index, message)
      error = assert_raises(RepositoryIndex::CategorisationError) do
        index.to_markdown
      end
      assert_equal message, error.message
    end

    it "renders a table row per category, in the order they're specified" do
      index = RepositoryIndex.new(
        repositories: [repository("dxw/b"), repository("yndajas/a")],
        categories: { "One" => ["yndajas/a"], "Two" => ["dxw/b"] },
      )

      assert_equal(
        "| category | repositories |\n" \
        "| -------- | ------------ |\n" \
        "| One | yndajas/ → [a](https://github.com/yndajas/a) |\n" \
        "| Two | dxw/ → [b](https://github.com/dxw/b) |",
        index.to_markdown,
      )
    end

    it "lists a category's repositories in the data's order" do
      index = RepositoryIndex.new(
        repositories: [repository("dxw/b"), repository("yndajas/a")],
        categories: { "Tools" => ["yndajas/a", "dxw/b"] },
      )

      assert_includes(
        index.to_markdown,
        "| Tools | [dxw/b](https://github.com/dxw/b), " \
        "[yndajas/a](https://github.com/yndajas/a) |",
      )
    end

    it "states a shared owner once" do
      index = RepositoryIndex.new(
        repositories: [repository("alphagov/signon")],
        categories: { "GOV.UK" => ["alphagov/signon"] },
      )

      assert_includes(
        index.to_markdown,
        "| GOV.UK | alphagov/ → " \
        "[signon](https://github.com/alphagov/signon) |",
      )
    end

    it "escapes pipes in category names" do
      index = RepositoryIndex.new(
        repositories: [repository("yndajas/a")],
        categories: { "This | that" => ["yndajas/a"] },
      )

      assert_includes(index.to_markdown, "| This \\| that |")
    end

    describe "when a category has no repositories" do
      it "raises an error naming the category" do
        index = RepositoryIndex.new(
          repositories: [repository("yndajas/a")],
          categories: { "One" => ["yndajas/a"], "Empty" => nil },
        )

        assert_categorisation_error(
          index,
          "Categories with no repositories: Empty",
        )
      end
    end

    describe "when a repository is in more than one category" do
      it "raises an error naming the repository" do
        index = RepositoryIndex.new(
          repositories: [repository("yndajas/a")],
          categories: { "One" => ["yndajas/a"], "Two" => ["yndajas/a"] },
        )

        assert_categorisation_error(
          index,
          "Repositories in more than one category: yndajas/a",
        )
      end
    end

    describe "when a categorised repository is missing from the data" do
      it "raises an error naming the repository" do
        index = RepositoryIndex.new(
          repositories: [repository("yndajas/a")],
          categories: { "One" => ["yndajas/a", "yndajas/missing"] },
        )

        assert_categorisation_error(
          index,
          "Categorised repositories missing from the data: yndajas/missing",
        )
      end
    end

    describe "when a repository isn't categorised" do
      it "raises an error naming the repository" do
        index = RepositoryIndex.new(
          repositories: [repository("yndajas/a"), repository("yndajas/b")],
          categories: { "One" => ["yndajas/a"] },
        )

        assert_categorisation_error(
          index,
          "Uncategorised repositories: yndajas/b",
        )
      end
    end

    describe "when there are several categorisation problems" do
      it "raises an error listing all of them" do
        index = RepositoryIndex.new(
          repositories: [repository("yndajas/a")],
          categories: { "One" => ["yndajas/missing"], "Empty" => nil },
        )

        assert_categorisation_error(
          index,
          "Categories with no repositories: Empty\n" \
          "Categorised repositories missing from the data: yndajas/missing\n" \
          "Uncategorised repositories: yndajas/a",
        )
      end
    end
  end

  describe "#insert_into" do
    it "replaces the content between the markers" do
      index = RepositoryIndex.new(
        repositories: [repository("yndajas/a")],
        categories: { "Misc" => ["yndajas/a"] },
      )
      readme = <<~MARKDOWN
        Before
        <!-- repository-index:start -->
        Old
        <!-- repository-index:end -->
        After
      MARKDOWN

      assert_equal(
        <<~MARKDOWN,
          Before
          <!-- repository-index:start -->

          | category | repositories |
          | -------- | ------------ |
          | Misc | yndajas/ → [a](https://github.com/yndajas/a) |

          <!-- repository-index:end -->
          After
        MARKDOWN
        index.insert_into(readme),
      )
    end

    it "raises when the README has no markers" do
      index = RepositoryIndex.new(repositories: [], categories: {})

      assert_raises(RepositoryIndex::MissingMarkersError) do
        index.insert_into("No markers")
      end
    end
  end
end
