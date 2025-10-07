# Use an official Python runtime as a parent image
FROM python:3.11-bookworm

# Set environment variables for non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: wget, gnupg for adding Chrome repo; unzip for ChromeDriver;
# curl and jq for fetching ChromeDriver URL; common Chrome runtime dependencies.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    gnupg \
    unzip \
    curl \
    jq \
    # Minimal dependencies for Chrome
    libglib2.0-0 \
    libnss3 \
    libgconf-2-4 \
    libfontconfig1 \
    libx11-6 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    libdrm2 \
    libgbm1 \
    libasound2 \
    # Clean up apt cache
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add Google Chrome's official repository and install the latest stable version
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list' && \
    apt-get update && \
    apt-get install -y google-chrome-stable --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Install matching ChromeDriver using Chrome for Testing (CfT) JSON endpoints
RUN CHROME_VERSION_FULL=$(google-chrome-stable --product-version) && \
    echo "Installed Chrome version: $CHROME_VERSION_FULL" && \
    CFT_JSON_URL="https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" && \
    echo "Fetching ChromeDriver versions from $CFT_JSON_URL" && \
    CHROMEDRIVER_URL=$(curl -s "$CFT_JSON_URL" | jq -r --arg CV "$CHROME_VERSION_FULL" '
        (.versions[] | select(.version == $CV) | .downloads.chromedriver[] | select(.platform=="linux64") | .url) //
        (
            # Fallback: find latest stable if exact match not found.
            # This gets the URL of the chromedriver for the highest version number listed in the JSON.
            .versions[-1].downloads.chromedriver[] | select(.platform=="linux64") | .url
        )
    ' | head -n 1) && \
    if [ -z "$CHROMEDRIVER_URL" ]; then \
        echo "Error: Could not determine ChromeDriver download URL for Chrome $CHROME_VERSION_FULL from CfT JSON." >&2; \
        CHROME_MAJOR_VERSION=$(echo "$CHROME_VERSION_FULL" | cut -d. -f1); \
        if [ "$CHROME_MAJOR_VERSION" -lt 115 ]; then \
            echo "Attempting fallback to old LATEST_RELEASE method for Chrome < 115" >&2; \
            OLD_LATEST_URL="https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${CHROME_MAJOR_VERSION}"; \
            CHROMEDRIVER_VERSION_NUMBER=$(wget -qO- "$OLD_LATEST_URL" || echo ""); \
            if [ -n "$CHROMEDRIVER_VERSION_NUMBER" ]; then \
                 CHROMEDRIVER_URL="https://chromedriver.storage.googleapis.com/${CHROMEDRIVER_VERSION_NUMBER}/chromedriver_linux64.zip"; \
            fi; \
        fi; \
        if [ -z "$CHROMEDRIVER_URL" ]; then echo "All fallbacks failed. Could not find ChromeDriver. Exiting." >&2; exit 1; fi; \
    fi && \
    echo "Using ChromeDriver download URL: $CHROMEDRIVER_URL" && \
    wget -q -O /tmp/chromedriver.zip "$CHROMEDRIVER_URL" && \
    unzip -q /tmp/chromedriver.zip -d /tmp/ && \
    # CfT zips often contain a directory like 'chromedriver-linux64', older zips might not.
    if [ -f /tmp/chromedriver-linux64/chromedriver ]; then \
        mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver; \
        rm -rf /tmp/chromedriver-linux64; \
    elif [ -f /tmp/chromedriver ]; then \
        mv /tmp/chromedriver /usr/local/bin/chromedriver; \
    else \
        echo "Error: chromedriver executable not found in expected location after unzip." >&2; exit 1; \
    fi && \
    rm /tmp/chromedriver.zip && \
    chmod +x /usr/local/bin/chromedriver && \
    # Verify chromedriver installation
    echo "ChromeDriver version: $(chromedriver --version)"

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container at /app
COPY src/requirements.txt .

# Install Python dependencies (Selenium should be in requirements.txt)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy the application source code
COPY src/ ./src/

# Default command to run the Python application
# Your Python script (e.g., src/usmsScraperV2.py) should initialize
# webdriver.Chrome() with options like --headless, --no-sandbox, --disable-dev-shm-usage
CMD ["python", "src/usmsScraperV2.py"]
