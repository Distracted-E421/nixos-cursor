defmodule CursorSyncTest do
  use ExUnit.Case
  doctest CursorSync.SyncEngine

  describe "SyncEngine" do
    test "initial stats are zero" do
      stats = CursorSync.SyncEngine.stats()
      
      assert stats.total_syncs == 0
      assert stats.successful_syncs == 0
      assert stats.failed_syncs == 0
      assert stats.messages_synced == 0
    end
  end

  describe "ExternalWriter" do
    test "stats returns zeros for non-existent database" do
      stats = CursorSync.Database.ExternalWriter.stats("/nonexistent/path.db")
      
      assert stats.conversations == 0
      assert stats.messages == 0
    end
  end
end
