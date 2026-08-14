FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /opt/money-trainer/training
COPY pyproject.toml ./
COPY money_trainer ./money_trainer
ARG INSTALL_ML=0
RUN if [ "$INSTALL_ML" = "1" ]; then \
      pip install --no-cache-dir '.[ml,yaml]'; \
    else \
      pip install --no-cache-dir .; \
    fi

ENTRYPOINT ["python", "-m", "money_trainer"]
CMD ["train", "--help"]
