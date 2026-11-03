# Local development image for the API. Not production-ready.
# No platform is set, so Docker builds for the machine it runs on.
FROM python:3.13-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv/api

# Copied before the code, so changing the code does not reinstall packages.
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check -r requirements.txt

COPY app ./app

# The files above stay owned by root, so this user can read but not change them.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin veloraug
USER veloraug

EXPOSE 8000

# 0.0.0.0 lets connections from outside the container reach Uvicorn. Which
# computers can reach the container is decided where the port is published.
CMD ["python", "-m", "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
