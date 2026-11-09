import os
from pathlib import Path

from flask import Flask, render_template_string

app = Flask(__name__)

APP_VERSION = Path(__file__).with_name("VERSION").read_text().strip()

PAGE = """<!doctype html>
<title>Hello World</title>
<h1>Hello, World!</h1>
<p>App version: {{ app_version }}</p>
<p>Image version: {{ image_version }}</p>
"""


@app.get("/")
def landing():
    return render_template_string(
        PAGE,
        app_version=APP_VERSION,
        image_version=os.environ.get("IMAGE_VERSION", "dev"),
    )


@app.get("/health")
def health():
    return {"status": "ok"}
