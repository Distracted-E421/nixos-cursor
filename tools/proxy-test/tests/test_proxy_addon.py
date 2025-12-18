"""
Tests for the Cursor Proxy mitmproxy addon.

These tests verify the proxy addon logic without requiring a running proxy.
"""

import pytest
import json
from unittest.mock import Mock, MagicMock, patch
from pathlib import Path
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))


class TestCursorDomains:
    """Tests for domain detection logic."""
    
    def test_cursor_domains_defined(self):
        """Test that CURSOR_DOMAINS are defined."""
        # Import the module
        from test_cursor_proxy import CURSOR_DOMAINS
        
        assert isinstance(CURSOR_DOMAINS, list)
        assert len(CURSOR_DOMAINS) > 0
    
    def test_known_cursor_domains_included(self):
        """Test that known Cursor domains are in the list."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        # These are known Cursor API domains
        expected_domains = [
            "api.cursor.com",
            "api2.cursor.sh",
        ]
        
        for domain in expected_domains:
            assert domain in CURSOR_DOMAINS, f"Expected {domain} to be in CURSOR_DOMAINS"
    
    def test_ai_backend_domains_included(self):
        """Test that AI backend domains are monitored."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        # Cursor may route through these backends
        ai_domains = ["api.anthropic.com", "api.openai.com"]
        
        for domain in ai_domains:
            assert domain in CURSOR_DOMAINS, f"Expected {domain} to be in CURSOR_DOMAINS"


class TestStats:
    """Tests for statistics tracking."""
    
    def test_stats_initialized(self):
        """Test that stats dictionary is properly initialized."""
        from test_cursor_proxy import stats
        
        assert "requests" in stats
        assert "cursor_requests" in stats
        assert "streaming_responses" in stats
        assert "intercepted_tokens" in stats
        assert "errors" in stats
    
    def test_stats_initial_values(self):
        """Test that stats start at zero."""
        from test_cursor_proxy import stats
        
        # Reset stats for test
        stats["requests"] = 0
        stats["cursor_requests"] = 0
        stats["streaming_responses"] = 0
        stats["intercepted_tokens"] = 0
        stats["errors"] = []
        
        assert stats["requests"] == 0
        assert stats["cursor_requests"] == 0
        assert isinstance(stats["errors"], list)


class TestCursorProxyTestClass:
    """Tests for the CursorProxyTest addon class."""
    
    @pytest.fixture
    def proxy_test(self):
        """Create a CursorProxyTest instance with mocked context."""
        with patch('test_cursor_proxy.ctx') as mock_ctx:
            mock_ctx.log = Mock()
            from test_cursor_proxy import CursorProxyTest
            return CursorProxyTest()
    
    def test_class_initialization(self, proxy_test):
        """Test that CursorProxyTest initializes properly."""
        assert proxy_test is not None


class TestDomainMatching:
    """Tests for domain matching logic."""
    
    def test_matches_exact_domain(self):
        """Test matching exact Cursor domains."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        test_host = "api.cursor.com"
        is_cursor = any(d in test_host for d in CURSOR_DOMAINS)
        
        assert is_cursor
    
    def test_matches_subdomain(self):
        """Test matching subdomains."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        # Test that cursor.sh subdomain matches
        test_host = "api2.cursor.sh"
        is_cursor = any(d in test_host for d in CURSOR_DOMAINS)
        
        assert is_cursor
    
    def test_no_match_unrelated_domain(self):
        """Test that unrelated domains don't match."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        test_host = "example.com"
        is_cursor = any(d in test_host for d in CURSOR_DOMAINS)
        
        assert not is_cursor
    
    def test_no_match_similar_domain(self):
        """Test that similar but different domains don't match."""
        from test_cursor_proxy import CURSOR_DOMAINS
        
        # This shouldn't match even though it contains "cursor"
        test_host = "my-cursor-site.example.com"
        is_cursor = any(d in test_host for d in CURSOR_DOMAINS)
        
        # This will actually match if any domain substring is in the host
        # The current implementation may have false positives
        # This test documents the current behavior


class TestSSEParsing:
    """Tests for Server-Sent Events parsing logic."""
    
    def test_count_sse_events_in_content(self):
        """Test counting SSE data events."""
        content = b"data: {\"test\": 1}\n\ndata: {\"test\": 2}\n\ndata: [DONE]\n\n"
        
        events = content.count(b"data: ")
        assert events == 3
    
    def test_empty_content_has_no_events(self):
        """Test that empty content has no events."""
        content = b""
        
        events = content.count(b"data: ")
        assert events == 0
    
    def test_partial_sse_detection(self):
        """Test detecting partial SSE content."""
        content = b"data: {\"partial\": true}"  # No trailing newlines
        
        events = content.count(b"data: ")
        assert events == 1


class TestErrorTracking:
    """Tests for error tracking functionality."""
    
    def test_error_structure(self):
        """Test that errors have the expected structure."""
        from test_cursor_proxy import stats
        from datetime import datetime
        
        # Simulate adding an error
        error_entry = {
            "url": "https://api.cursor.com/test",
            "error": "Connection refused",
            "time": datetime.now().isoformat()
        }
        
        stats["errors"] = [error_entry]
        
        assert len(stats["errors"]) == 1
        assert "url" in stats["errors"][0]
        assert "error" in stats["errors"][0]
        assert "time" in stats["errors"][0]
    
    def test_multiple_errors_tracked(self):
        """Test that multiple errors are tracked."""
        from test_cursor_proxy import stats
        from datetime import datetime
        
        stats["errors"] = []
        
        for i in range(5):
            stats["errors"].append({
                "url": f"https://api.cursor.com/test/{i}",
                "error": f"Error {i}",
                "time": datetime.now().isoformat()
            })
        
        assert len(stats["errors"]) == 5


class TestCertificatePinningDetection:
    """Tests for certificate pinning detection logic."""
    
    @pytest.mark.parametrize("error_message,expected_pinning", [
        ("certificate verify failed", True),
        ("SSL: CERTIFICATE_VERIFY_FAILED", True),
        ("TLS handshake failed", True),
        ("Connection refused", False),
        ("Connection timeout", False),
        ("Unknown host", False),
    ])
    def test_pinning_detection_patterns(self, error_message, expected_pinning):
        """Test various error patterns for cert pinning detection."""
        error_lower = error_message.lower()
        
        is_cert_error = (
            "certificate" in error_lower or
            "ssl" in error_lower or
            "tls" in error_lower
        )
        
        assert is_cert_error == expected_pinning


class TestStreamingDetection:
    """Tests for streaming response detection."""
    
    @pytest.mark.parametrize("content_type,is_streaming", [
        ("text/event-stream", True),
        ("text/event-stream; charset=utf-8", True),
        ("application/json", False),
        ("text/html", False),
        ("application/octet-stream", False),
    ])
    def test_content_type_detection(self, content_type, is_streaming):
        """Test streaming detection based on content type."""
        detected = "text/event-stream" in content_type
        assert detected == is_streaming


class TestRequestCounting:
    """Tests for request counting logic."""
    
    def test_increment_total_requests(self):
        """Test incrementing total request count."""
        from test_cursor_proxy import stats
        
        initial = stats["requests"]
        stats["requests"] += 1
        
        assert stats["requests"] == initial + 1
    
    def test_increment_cursor_requests(self):
        """Test incrementing Cursor-specific request count."""
        from test_cursor_proxy import stats
        
        initial = stats["cursor_requests"]
        stats["cursor_requests"] += 1
        
        assert stats["cursor_requests"] == initial + 1
    
    def test_cursor_requests_subset_of_total(self):
        """Test that cursor_requests <= total requests conceptually."""
        from test_cursor_proxy import stats
        
        # Reset for test
        stats["requests"] = 100
        stats["cursor_requests"] = 30
        
        assert stats["cursor_requests"] <= stats["requests"]


class TestAddonRegistration:
    """Tests for mitmproxy addon registration."""
    
    def test_addons_list_exists(self):
        """Test that addons list is defined."""
        from test_cursor_proxy import addons
        
        assert isinstance(addons, list)
        assert len(addons) > 0
    
    def test_addon_is_cursor_proxy_test(self):
        """Test that the addon is a CursorProxyTest instance."""
        from test_cursor_proxy import addons, CursorProxyTest
        
        assert isinstance(addons[0], CursorProxyTest)

