from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os, webbrowser
os.chdir(Path(__file__).resolve().parent)
url = 'http://127.0.0.1:8000/'
print(f'KingQayum CRM is running at {url}\nPress Ctrl+C to stop.')
try: webbrowser.open(url)
except Exception: pass
ThreadingHTTPServer(('127.0.0.1', 8000), SimpleHTTPRequestHandler).serve_forever()
