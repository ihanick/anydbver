import os
import logging

COMMAND_TIMEOUT=600
DEFAULT_PASSWORD='verysecretpassword1^'
DEFAULT_SERVER_ID=50
ANYDBVER_DIR = os.path.dirname(os.path.realpath(__file__))

logger = logging.getLogger('AnyDbVer')
logger.setLevel(logging.INFO)
