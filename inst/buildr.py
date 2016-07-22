import hashlib
import json
import os
import shutil
import subprocess
import time

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
    return ('source', 'binary')


class Buildr:
    def __init__(self, path='.'):
        # should spawn R here to check packages I think, and set up a
        # temporary library, as we don't want to fuck up the main one.
        self.paths = paths(path)
        self.lib_host = os.environ['R_LIBS_USER']
        self.reset()

    def reset(self, async=False):
        for p in self.paths.itervalues():
            dir_create(p)
        # If this fails, it's all bad.
        os.environ['R_LIBS_USER'] = self.lib_host
        args = ['Rscript', '-e',
                'buildr:::bootstrap("%s")' % self.paths['lib']]
        if async:
            self.active = process('active', args, None)
        else:
            code = subprocess.call(args)
            if code != 0:
                raise Exception('Error running bootstrap script')
            self.active = None
        os.environ['R_LIBS_USER'] = self.paths['lib']
        self.queue = []
        self.log('buildr', 'starting')
        return self.active

    def package_list(self, package_type, translate):
        pkgs = os.listdir(self.paths[package_type])
        if translate:
            if package_type == "source":
                pkgs = [read_file(os.path.join(self.paths['filename'], i))
                        for i in pkgs]
            else:
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

    def queue_build(self, filename):
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
            self.log(package_id, 'queuing')
            self.queue.append(package_id)
        return package_id

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
        args = ['Rscript', '-e',
                'update.packages("%s", ask=FALSE)' % self.paths['lib']]
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
        args = ['Rscript', '-e',
                'buildr:::build_binary_main("%s", "%s", "%s", "%s")' % (
                    package_id, self.paths['source'], self.paths['binary'],
                    self.paths['info'])]
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
        if id != 'upgrade' and p != 0:
            with open(os.path.join(self.paths['info'], id), 'w') as file:
                file.write(json.dumps({'id': id, 'hash': id}))
        self.active = None

    def log(self, id, message):
        log_str = '[%s] (%-32s) %s' % (
            time.strftime('%Y-%m-%d %H:%M:%S'), id, message)
        with open(os.path.join(self.paths['log'], 'queue'), 'a') as logfile:
            logfile.write(log_str + "\n")
        print log_str

def read_file(filename):
    with open(filename, 'r') as f:
        return f.read()
