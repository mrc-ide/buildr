import hashlib
import json
import os
import shutil
import subprocess
import time
import re

# All the R stuff will be done async.  So we'll keep a queue of things
# to run and keep track of when it has completed, while avoiding
# blocking.  This won't be amazingly lovely, but it should work, and
# we're only after something simple here.

# Directories that we need:
#
#   lib - the R library that we'll accumulate
#   source - a directory of source packages
#   binary - a directory of binary packages
#   log - a directory of log files, from each build
#   info - a place to stash json information
#   filenames - where original filenames are stored

def paths(root):
    return {'root':     root,
            'lib':      os.path.join(root, 'lib'),
            'source':   os.path.join(root, 'source'),
            'binary':   os.path.join(root, 'binary'),
            'info':     os.path.join(root, 'info'),
            'filename': os.path.join(root, 'filename'),
            'incoming': os.path.join(root, 'incoming'),
            'log':      os.path.join(root, 'log')}


def md5sum(filename):
    hasher = hashlib.md5()
    with open(filename, 'rb') as file:
        hasher.update(file.read())
    return hasher.hexdigest()


def dir_create(path):
    if not os.path.exists(path):
        os.makedirs(path)


def process(id, args, log):
    fh = None if log is None else open(log, 'w')
    process = subprocess.Popen(args, stdout = fh, stderr = fh)
    return {'id': id, 'process': process, 'log': log, 'log_handle': fh}


def package_types():
    return ('source', 'binary', 'lib')


def is_exe(fpath):
    return os.path.isfile(fpath) and os.access(fpath, os.X_OK)


def clean_path(path):
    return path if os.name != 'nt' else path.replace("\\", "/")


def sys_which(program):
    fpath, fname = os.path.split(program)
    if fpath:
        if is_exe(program):
            return program
    else:
        for path in os.environ['PATH'].split(os.pathsep):
            path = path.strip('"')
            exe_file = os.path.join(path, program)
            if is_exe(exe_file):
                return exe_file
    return None


def find_Rscript(path):
    rscript = 'Rscript.exe' if os.name == 'nt' else 'Rscript'
    if path is None:
        path = sys_which(rscript)
        if path is None:
            raise Exception('Did not find Rscript on path')
    else:
        if os.path.isdir(path):
            path = os.path.join(path, rscript)
        if not is_exe(path):
            raise Exception('Did not find Rscript at given path')
    return path


def rversion(rscript):
    version = subprocess.check_output([rscript, '--version'],
                                      stderr=subprocess.STDOUT)
    return version.split('\n', 1)[0]


class Buildr:
    def __init__(self, root='.', R=None):
        self.paths = paths(root)
        self.Rscript = find_Rscript(R)
        self.Rversion = rversion(self.Rscript)
        self.reset()

    def reset(self, async=False):
        for p in self.paths.itervalues():
            dir_create(p)
        self.active = None
        self.queue = []
        self.log('Rscript', self.Rscript)
        self.log('R',       self.Rversion)
        self.log('buildr', 'starting')
        return self.active

    def package_list(self, package_type, translate):
        pkgs = os.listdir(self.paths[package_type])
        if translate:
            if package_type == 'source':
                pkgs = [read_file(os.path.join(self.paths['filename'], i))
                        for i in pkgs]
            elif package_type == 'binary':
                pkgs = [self.package_info(i)['filename_binary']
                        for i in pkgs]
        return pkgs

    def package_status(self, package_id):
        if os.path.exists(os.path.join(self.paths['binary'], package_id)):
            return 'COMPLETE'
        elif os.path.exists(os.path.join(self.paths['info'], package_id)):
            return 'ERROR'
        elif package_id in self.queue:
            return 'PENDING'
        elif os.path.exists(os.path.join(self.paths['source'], package_id)):
            return 'RUNNING'
        else:
            return 'UNKNOWN'

    def package_info(self, package_id):
        filename_info = os.path.join(self.paths['info'], package_id)
        if not os.path.exists(filename_info):
            return None
        return json.loads(read_file(filename_info))

    def source_info(self, package_id):
        filename_source = os.path.join(self.paths['filename'], package_id)
        if not os.path.exists(filename_source):
            return None
        return {'hash_source': package_id,
                'filename_source': read_file(filename_source)}

    def queue_status(self):
        return self.queue

    def queue_submit(self, filename, queue):
        package_id = md5sum(filename)
        with open(os.path.join(self.paths['filename'], package_id), 'w') as f:
            f.write(os.path.basename(filename))
        filename_source = os.path.join(self.paths['source'], package_id)
        filename_binary = os.path.join(self.paths['binary'], package_id)
        if os.path.exists(filename_binary) or \
           package_id in self.queue or \
           (self.active and self.active['id'] == package_id):
            self.log(package_id, 'skipping')
        else:
            shutil.copyfile(filename, filename_source)
            if queue:
                self.queue_add(package_id)
        return package_id

    def queue_add(self, package_id):
        # clean up any previous attempts, as these will confuse clients
        path_info = os.path.join(self.paths['info'], package_id)
        path_log = os.path.join(self.paths['log'], package_id)
        if os.path.exists(path_info):
            os.remove(path_info)
        if os.path.exists(path_log):
            os.remove(path_log)
        self.log(package_id, 'queuing')
        self.queue.append(package_id)

    def queue_special(self, special):
        run = False
        if special in self.queue:
            self.log(special, 'skipping - already queued')
        elif self.active and self.active['id'] is not special:
            self.log(special, 'skipping - already running')
        else:
            run = True
            self.log(special, 'queuing')
            self.queue.insert(0, special)
        return run

    def run_upgrade(self):
        # NOTE: does not use _any_ non-base packages/functions because
        # otherwise we'd get file locking issues on windows.
        args = [self.Rscript, '-e',
                "update.packages('%s', ask=FALSE)" %
                clean_path(self.paths['lib'])]
        return process('upgrade', args, None)

    def run_reset(self):
        shutil.rmtree(self.paths['info'])
        shutil.rmtree(self.paths['filename'])
        shutil.rmtree(self.paths['lib'])
        shutil.rmtree(self.paths['source'])
        shutil.rmtree(self.paths['binary'])
        shutil.rmtree(self.paths['log'])
        shutil.rmtree(self.paths['incoming'])
        return self.reset(True)

    def run_build(self, package_id):
        args = [self.Rscript, '-e',
                "buildr:::build_binary_main('%s', '%s', '%s', '%s', '%s')" % (
                    package_id,
                    clean_path(self.paths['source']),
                    clean_path(self.paths['binary']),
                    clean_path(self.paths['info']),
                    clean_path(self.paths['lib']))]
        logfile = os.path.join(self.paths['log'], package_id)
        return process(package_id, args, logfile)

    def run(self):
        if self.active:
            p = self.active['process'].poll()
            if p is None:
                self.log(self.active['id'], 'still running')
                return None
            self.cleanup(p)
        self.run_next()

    def run_next(self):
        if len(self.queue) == 0:
            return None
        else:
            id = self.queue.pop()
            self.log(id, 'starting')
            if id == 'upgrade':
                self.active = self.run_upgrade()
            elif id == 'reset':
                self.active = self.run_reset()
            else:
                self.active = self.run_build(id)

    def cleanup(self, p):
        self.log(self.active['id'], 'complete with code %d' % p)
        if self.active['log_handle']:
            self.active['log_handle'].close()
        id = self.active['id']
        batch = id.find(',') > 0
        if batch:
            split_logs(self.paths['log'], id)
        if id != 'upgrade' and p != 0:
            for i in id.split(','):
                fsrc = read_file(os.path.join(self.paths['filename'], id))
                with open(os.path.join(self.paths['info'], id), 'w') as file:
                    file.write(json.dumps({'id': id, 'hash': id,
                                           'filename_source': fsrc}))
        self.active = None

    def log(self, id, message):
        log_str = '[%s] (%-32s) %s' % (
            time.strftime('%Y-%m-%d %H:%M:%S'), id, message)
        with open(os.path.join(self.paths['log'], 'queue'), 'a') as logfile:
            logfile.write(log_str + '\n')
        print log_str

def read_file(filename):
    with open(filename, 'r') as f:
        return f.read()

def read_lines(filename):
    with open(filename, 'r') as f:
        return f.readlines()

def split_logs(path, id):
    path_log = os.path.join(path, id)
    log = read_lines(path_log)
    pat = re.compile('^BUILDR: ([a-f0-9]+) ')
    res = []
    for i, l in enumerate(log):
        m = pat.match(l)
        if m:
            res.append((i, m.group(1)))
    res.append((len(log), None))
    for i in xrange(len(res) - 1):
        with open(os.path.join(path, res[i][1]), 'w') as logfile:
            logfile.write(''.join(log[res[i][0]:res[i + 1][0]]))
