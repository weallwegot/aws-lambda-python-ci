# chord-ci

### Usage

- This repository is meant to be cloned into Github Actions runner or an equivalent CI/build tool. The scripts are then used to deploy Lambda functions into the cloud.

- For examples of how to build a pipeline with Github Actions check out `examples/github-actions-deployment.yaml`

### Behind the Scenes

- Most of the parameters are pulled from a configuration file that comes with each lambda being deployed and will look like this

```
[configuration]
function-name=org-setting-update
description=update settings and templates
runtime=python3.6
handler=app.handler
region=TAKEN-FROM-DEFAULT-PROFILE
timeout=240
memory-size=256
role=TAKEN-FROM-DEFAULT-IF-NOT-SPECIFIED

[environment]
env1=val1
env2=val2
env3=val3
```

- the parameters are fed into the Python script `deploy_orchestration.py` which makes use of the vanilla library `configparser` to read in the configuration file. Python was easier to do some of the file reading and string parsing for me

- the vast majority of the AWS interaction and packaging of lambdas is done in the bash script `aws-lambda-deploy.sh` using AWS cli tool

- the high level process is:
    - check if the lambda we are deploying already exists
    - download any dependencies via `requirements.txt`
    - zip up the local files to make a lambda deployment package
    - send the zipped package to the cloud
    - add environment variables
    - publish a version to lock the code in place once deployed
    - add an alias to denote production vs development environment
    - clean up deployment artifacts