# -*- coding: utf-8 -*-
"""Orchestrates deployment of python lambda by parsing inputs and passing to shell script."""
# !/usr/bin/env python3

import configparser
import json
import logging
import subprocess
import sys

ALIAS = sys.argv[1]
# resource role is optional and will be overwritten by any values provided in deployment config
RESOURCE_ROLE = sys.argv[2]
S3_BUCKET_FOR_DEPLOYMENT = sys.argv[3]
# keep the app environment as an environment value
APP_ENVIRONMENT_KEY = sys.argv[4]

cfg = configparser.ConfigParser()
# https://stackoverflow.com/questions/1611799/preserve-case-in-configparser
cfg.optionxform = str
cfg.read('deployment-config.ini')

if not S3_BUCKET_FOR_DEPLOYMENT:
    raise ValueError(f"No s3 bucket provided for deployment artifacts")

# parse lambda configuration parameters
CONFIG_PARAMS = {}
for config_tuple in cfg.items('configuration'):
    name = config_tuple[0]
    val = config_tuple[1]
    CONFIG_PARAMS[name] = val

if 'role' in CONFIG_PARAMS.keys():
    RESOURCE_ROLE = CONFIG_PARAMS['role']


# https://stackoverflow.com/questions/5466451/how-can-i-print-literal-curly-brace-characters-in-python-string-and-also-use-fo#5466478
VARS_STR_TEMPLATE = "Variables={{{}}}"
env_vars = ""
for config_tuple in cfg.items('environment'):
    env_vars += "{k}={v},".format(k=config_tuple[0], v=config_tuple[1])

# add app environment to the OS values &  use the alias as the same
env_vars += "{k}={v},".format(k=f"{APP_ENVIRONMENT_KEY}", v=ALIAS)

if env_vars.endswith(","):
    env_vars = env_vars[:-1]
VARS_STR = VARS_STR_TEMPLATE.format(env_vars)
print("Parsed environment variables:\n{}".format(VARS_STR))


def is_func_new(funcname):
    """
    determine if function being deployed is brand new or just needs updates
    """
    bashCommand = "aws lambda get-function \
    --function-name {fname}".format(
        fname=funcname
    )

    try:
        subprocess.check_output(bashCommand.split())
    except subprocess.CalledProcessError as e:
        # if the error is raised it means the functions does not exist
        logging.error(e)
        print("returning True")
        return True
    print("returning False")
    return False


def deploy_lambda(new):
    """
    ISNEW=$1
    RESOURCE_ROLE=$2
    ALIAS=$3

    FNAME=$4
    HANDLER=$5
    TIMEOUT=$6
    MEMSIZE=$7
    DESC=$8
    ENV=$9
    RUNTIME=${10}
    REGION=${11}
    """
    #  the -e makes the script exit when functions fail. the -x enables debugging/traces
    # some warnings about -e: http://mywiki.wooledge.org/BashFAQ/105
    bashCommand = "bash -e -x CI/aws-lambda-deploy.sh \
    {isnew} \
    {AWS_LAMBDA_ROLE} \
    {alias} \
    {funcname} {handler} {timeout} {memsize} '{desc}' '{env}' '{runtime}' '{region}' '{s3_bucket}'".format(
        AWS_LAMBDA_ROLE=RESOURCE_ROLE,
        isnew=new,
        alias=ALIAS,
        funcname=CONFIG_PARAMS['function-name'],
        desc=CONFIG_PARAMS['description'],
        runtime=CONFIG_PARAMS['runtime'],
        handler=CONFIG_PARAMS['handler'],
        region=CONFIG_PARAMS['region'],
        timeout=CONFIG_PARAMS['timeout'],
        memsize=CONFIG_PARAMS['memory-size'],
        s3_bucket=S3_BUCKET_FOR_DEPLOYMENT,
        env=VARS_STR
    )

    # https://docs.python.org/3/library/subprocess.html#subprocess.run
    completed_process = subprocess.run(bashCommand, stdout=subprocess.PIPE, shell=True)
    return_code = completed_process.returncode
    logging.info(completed_process)
    if return_code != 0:
        raise Exception(f"Lambda deployment was unsuccessful. Attempted to run: {bashCommand}")

if __name__ == "__main__":
    logging.info("deploying...\n")
    deploy_lambda(new=is_func_new(CONFIG_PARAMS['function-name']))
