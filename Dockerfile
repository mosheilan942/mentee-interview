# Build stage: install pinned dependencies into a virtualenv
FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f AS build
RUN python -m venv /venv
COPY app/requirements.txt /tmp/requirements.txt
RUN /venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt

# Runtime stage: only the virtualenv and the app code
FROM python:3.14-slim@sha256:9aaa474097d094040649f2162a627c0049b408f52138d980916788d80f04802f
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/venv/bin:$PATH
RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /venv /venv
COPY app/hello_world.py app/VERSION ./

# Last on purpose: a new version must not invalidate the cached layers above
ARG IMAGE_VERSION=dev
ENV IMAGE_VERSION=$IMAGE_VERSION
LABEL org.opencontainers.image.version=$IMAGE_VERSION

USER 10001
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "--no-control-socket", "hello_world:app"]
