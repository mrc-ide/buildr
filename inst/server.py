# To debug;
#   import ipdb; ipdb.set_trace()
import os
import flask
from werkzeug import secure_filename

import buildr

app = flask.Flask(__name__)
obj = buildr.Buildr()

@app.route('/')
def index():
    return flask.jsonify('This is buildr')

@app.route("/packages/<package_type>")
def packages(package_type):
    check_package_type(package_type)
    packages = os.listdir(obj.paths[package_type])
    return flask.jsonify(packages)

@app.route("/status/<package_id>")
def status(package_id):
    if package_id == "queue":
        ret = obj.queue_status()
    else:
        ret = obj.package_status(package_id)
    return flask.jsonify(ret)

@app.route("/info/<package_id>")
def info(package_id):
    ret = obj.package_info(package_id)
    if ret:
        return flask.jsonify(ret)
    else:
        return err_not_found()

@app.route("/source_info/<package_id>")
def source_info(package_id):
    ret = obj.source_info(package_id)
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
        # import ipdb; ipdb.set_trace()
        if n is not None and len(dat) > n:
            dat = dat[-n:]
        return flask.jsonify(''.join(dat))

@app.route("/download/<package_id>/<package_type>")
def download(package_id, package_type):
    check_package_type(package_type)
    path = os.path.join(obj.paths[package_type], package_id)
    if not os.path.exists(path):
        return err_not_found()
    return flask.send_file(os.path.abspath(path),
                           'application/octet-stream')

@app.route("/submit/<package_name>", methods=["POST"])
def submit(package_name):
    tmpfile = os.path.join(obj.paths['root'], 'incoming',
                           secure_filename(os.path.basename(package_name)))
    with open(tmpfile, 'wb') as file:
        file.write(flask.request.data)
    package_id = obj.queue_build(tmpfile)
    os.remove(tmpfile)
    return flask.jsonify(package_id)

@app.route("/upgrade", methods=["PATCH"])
def upgrade():
    return flask.jsonify(obj.queue_upgrade())

@app.after_request
def process_queue(response):
    obj.run()
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
