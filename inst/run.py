#!/usr/bin/env python
import argparse
import os
import server

parser = argparse.ArgumentParser(description='Run a buildr server.')
parser.add_argument('--root', dest='root', default='.',
                    help='path for root of server')
parser.add_argument('--port', dest='port', default='8765',
                    help='port to run server on')
parser.add_argument('--expose', dest='expose', action='store_true',
                    help='Exose the server to the world?')

args = parser.parse_args()
host = "0.0.0.0" if args.expose else "127.0.0.1"

server.main(args.root, host, args.port)
