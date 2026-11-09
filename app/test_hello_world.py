from pathlib import Path

import pytest

import hello_world


@pytest.fixture
def client():
    return hello_world.app.test_client()


def test_landing_page_shows_app_version_from_version_file(client):
    app_version = Path(hello_world.__file__).with_name("VERSION").read_text().strip()
    page = client.get("/").get_data(as_text=True)
    assert f"App version: {app_version}" in page


def test_landing_page_shows_image_version_from_env(client, monkeypatch):
    monkeypatch.setenv("IMAGE_VERSION", "1.0.5")
    page = client.get("/").get_data(as_text=True)
    assert "Image version: 1.0.5" in page


def test_image_version_defaults_to_dev_when_not_set(client, monkeypatch):
    monkeypatch.delenv("IMAGE_VERSION", raising=False)
    page = client.get("/").get_data(as_text=True)
    assert "Image version: dev" in page


def test_health_returns_ok(client):
    assert client.get("/health").status_code == 200
