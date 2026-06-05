import os

import uvicorn


def main() -> None:
    port = int(os.environ.get("PORT", "8088"))
    uvicorn.run("main:app", host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    main()
