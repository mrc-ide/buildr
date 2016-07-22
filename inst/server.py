#!/usr/bin/env python
# To debug;
#   import ipdb; ipdb.set_trace()
import os
import flask
from werkzeug import secure_filename

import buildr

app = flask.Flask(__name__)

@app.route('/')
def index():
    return flask.jsonify('This is buildr')

@app.route("/packages/<package_type>")
def packages(package_type):
    check_package_type(package_type)
    translate = flask.request.args.get('translate').lower() == 'true'
    packages = app.buildr.package_list(package_type, translate)
    return flask.jsonify(packages)

@app.route("/status/<package_id>")
def status(package_id):
    if package_id == "queue":
        ret = app.buildr.queue_status()
    else:
        ret = app.buildr.package_status(package_id)
    return flask.jsonify(ret)

@app.route("/info/<package_id>")
def info(package_id):
    ret = app.buildr.package_info(package_id)
    if ret:
        return flask.jsonify(ret)
    else:
        return err_not_found()

@app.route("/source_info/<package_id>")
def source_info(package_id):
    ret = app.buildr.source_info(package_id)
    if ret:
        return flask.jsonify(ret)
    else:
        return err_not_found()

@app.route("/log/<package_id>")
def log(package_id):
    n = flask.request.args.get('n')
    if n is not None:
        n = int(n)
    filename = app.buildr.paths['log'] + '/' + package_id
    if not os.path.exists(filename):
        return err_not_found()
    with open(filename, 'r') as f:
        dat = f.readlines()
        if n is not None and len(dat) > n:
            dat = dat[-n:]
        return flask.jsonify(''.join(dat))

@app.route("/download/<package_id>/<package_type>")
def download(package_id, package_type):
    check_package_type(package_type)
    path = os.path.join(app.buildr.paths[package_type], package_id)
    if not os.path.exists(path):
        return err_not_found()
    return flask.send_file(os.path.abspath(path),
                           'application/octet-stream')

@app.route("/submit/<package_name>", methods=["POST"])
def submit(package_name):
    tmpfile = os.path.join(app.buildr.paths['root'], 'incoming',
                           secure_filename(os.path.basename(package_name)))
    with open(tmpfile, 'wb') as file:
        file.write(flask.request.data)
    package_id = app.buildr.queue_build(tmpfile)
    os.remove(tmpfile)
    return flask.jsonify(package_id)

@app.route("/upgrade", methods=["PATCH"])
def upgrade():
    return flask.jsonify(app.buildr.queue_special('upgrade'))

# TODO: ths should have a pin on it or something.  That's pretty
# annoying to get right but would be useful.  But we're assuming here
# that we're running in a non-hostile environment.
@app.route("/reset", methods=["PATCH"])
def reset():
    return flask.jsonify(app.buildr.queue_special('reset'))

@app.after_request
def process_queue(response):
    app.buildr.run()
    return response

def err_not_found(error=None):
    message = {
        'status': 404,
        'message': 'Not found: ' + flask.request.url
    }
    resp = flask.jsonify(message)
    resp.status_code = 404
    return resp

class InvalidUsage(Exception):
    status_code = 400

    def __init__(self, message, status_code=None, payload=None):
        Exception.__init__(self)
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        self.payload = payload

    def to_dict(self):
        rv = dict(self.payload or ())
        rv['message'] = self.message
        return rv

def check_package_type(package_type):
    if package_type not in buildr.package_types():
        raise InvalidUsage("Invalid package type", status_code=400)

def sys_getenv(name, default=None):
    if name in os.environ:
        return os.environ[name]
    else:
        return default

if __name__ == "__main__":
    app.buildr = buildr.Buildr(sys_getenv("BUILDR_ROOT", "."))
    app.run('0.0.0.0', sys_getenv("BUILDR_PORT", 8765))
