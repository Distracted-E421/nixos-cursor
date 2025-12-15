defmodule CursorDocsTest do
  use ExUnit.Case
  doctest CursorDocs

  describe "search/2" do
    test "returns empty list for no matches" do
      # This is a placeholder test
      # Real tests would require database setup
      assert {:ok, []} = CursorDocs.search("nonexistent query xyz123")
    end
  end

  describe "list/0" do
    test "returns list of sources" do
      assert {:ok, sources} = CursorDocs.list()
      assert is_list(sources)
    end
  end
end

