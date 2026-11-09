import pytest

from check_version import check


def test_rejects_version_that_is_not_semver():
    assert "not MAJOR.MINOR.PATCH" in check(previous="1.0.0", current="1.0", app_changed=False)


def test_first_release_accepts_any_valid_version():
    assert check(previous=None, current="1.0.0", app_changed=True) is None


def test_rejects_app_change_without_version_bump():
    assert "not bumped" in check(previous="1.0.0", current="1.0.0", app_changed=True)


def test_accepts_same_version_when_only_image_changed():
    assert check(previous="1.0.0", current="1.0.0", app_changed=False) is None


@pytest.mark.parametrize("current", ["1.2.4", "1.3.0", "2.0.0"])
def test_accepts_valid_next_versions(current):
    assert check(previous="1.2.3", current=current, app_changed=True) is None


@pytest.mark.parametrize("current", ["3.0.0", "1.2.5", "1.2.2", "1.3.1"])
def test_rejects_skipped_or_backward_versions(current):
    assert "not a valid next version" in check(previous="1.2.3", current=current, app_changed=True)
