"""Tests for the container health check, against a real local HTTP server."""

import threading
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from portfolio_api.healthcheck import check, main


def serve(status: int) -> tuple[ThreadingHTTPServer, int]:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - the name is fixed by http.server
            self.send_response(status if self.path == "/health" else 404)
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:  # noqa: A002
            pass  # keep the test output quiet

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, int(server.server_address[1])


@pytest.fixture
def healthy_port() -> Iterator[int]:
    server, port = serve(200)
    yield port
    server.shutdown()
    server.server_close()


@pytest.fixture
def failing_port() -> Iterator[int]:
    server, port = serve(500)
    yield port
    server.shutdown()
    server.server_close()


def test_check_is_true_when_health_answers_200(healthy_port: int) -> None:
    assert check(healthy_port) is True


def test_check_is_false_on_an_error_status(failing_port: int) -> None:
    assert check(failing_port) is False


def test_check_is_false_when_nothing_listens() -> None:
    server, port = serve(200)
    server.shutdown()
    server.server_close()  # the port is now closed
    assert check(port, timeout=0.5) is False


def test_main_uses_the_port_from_the_settings(
    healthy_port: int, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("PORT", str(healthy_port))
    assert main() == 0


def test_main_fails_when_the_app_is_not_reachable(
    failing_port: int, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("PORT", str(failing_port))
    assert main() == 1
