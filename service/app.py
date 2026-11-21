
import os
import socket
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "app": os.getenv("APP_NAME", ""),
        "version": os.getenv("VERSION", ""),
        "pod": socket.gethostname()
    }), 200


@app.route("/healthz", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8012)
