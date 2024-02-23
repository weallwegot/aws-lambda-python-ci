#!/bin/bash


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
S3_BUCKET_FOR_DEPLOYMENT=${12}



checkAndWait(){
    # check state & last update progress
    # https://docs.aws.amazon.com/cli/latest/reference/lambda/get-function.html
    # https://github.com/claudiajs/claudia/issues/226

    # https://stackoverflow.com/questions/43291389/using-jq-to-assign-multiple-output-variables
    read LambdaState LambdaStateReason LambdaLastUpdateStatus LambdaLastUpdateStatusReason < <(echo $(aws lambda get-function --function-name  "$FNAME" | jq -r '.Configuration.State, .Configuration.StateReason, .Configuration.LastUpdateStatus, .Configuration.LastUpdateStatusReason')) 

    # https://www.diskinternals.com/linux-reader/bash-if-string-not-empty/
    if [ -n "$LambdaState" ] && [ -n "$LambdaStateReason" ] && [ -n "$LambdaLastUpdateStatus" ] && [ -n "$LambdaLastUpdateStatusReason" ]
    then
        echo "Lambda State: $LambdaState" >&2
        echo "Lambda State Reason: $LambdaStateReason" >&2
        echo "Lambda Last Update Status: $LambdaLastUpdateStatus" >&2
        echo "Lambda Last Update Status Reason: $LambdaLastUpdateStatusReason" >&2
    else
        echo "Was unable to read LambdaState and Update Status." >&2
        exit 1
    fi

    i=0

    # check to see if the status is Active & Successful
    while [ "$LambdaState" != "Active" -o "$LambdaLastUpdateStatus" != "Successful" ]
    do
        echo "sleeping for 5 seconds to wait for LambdaState to change from $LambdaState & LambdaLastUpdateStatus to change from $LambdaLastUpdateStatus" >&2

        sleep 5
        read LambdaState LambdaStateReason LambdaLastUpdateStatus LambdaLastUpdateStatusReason < <(echo $(aws lambda get-function --function-name  "$FNAME" | jq -r '.Configuration.State, .Configuration.StateReason, .Configuration.LastUpdateStatus, .Configuration.LastUpdateStatusReason'))

        ((i++))

        # if we've slept for over 30 seconds, lets just give it one more go.
        if [ $i -gt 6 ]
        then
            echo "sleeping for 25 seconds as a last ditch effort to let previous step finish" >&2
            sleep 30
            break
        fi

    done

}

deployLambdaFunctionWithCheckIfNew() {


    # check if lambda is done with previous step
    checkAndWait || exit 1


    # $1 is the parameter passed that says whether or not the function is a new one
    if [ $1 == "True" ]
    then
        echo "deploying brand new lambda function" >&2
        # include publish here because it happens WITH the proper configuration
        LambdaCodeVersion=$(aws lambda create-function \
            --function-name $FNAME \
            --handler $HANDLER \
            --timeout $TIMEOUT \
            --memory-size $MEMSIZE \
            --code "S3Bucket=${S3_BUCKET_FOR_DEPLOYMENT},S3Key=${FNAME},S3ObjectVersion=${2}" \
            --runtime $RUNTIME \
            --environment "$ENV" \
            --role "$RESOURCE_ROLE" \
            --description "$DESC" \
            --publish | jq -r '.Version') 

    elif [ $1 == "False" ]
    then
        echo "updating an existing lambda function" >&2

        # update function code to point to the recently uploaded s3 file
        # don't publish because there's no way to update the configuration of a published version
        # ${2} is a parameter that gets passed in it is the s3 object version ID of the uploaded file
        aws lambda update-function-code \
            --function-name "${FNAME}" \
            --s3-bucket "${S3_BUCKET_FOR_DEPLOYMENT}" \
            --s3-key "${FNAME}/function.zip" \
            --s3-object-version "${2}"\
            --no-publish \
            || exit 1


        # check if lambda is done with previous step
        checkAndWait || exit 1

        # update function configuration (echo to higher than std.out so its displayed)
        echo "updating lambda function configuration" >&2

        aws lambda update-function-configuration \
            --function-name "$FNAME" \
            --handler "$HANDLER" \
            --timeout "$TIMEOUT" \
            --memory-size $MEMSIZE \
            --runtime $RUNTIME \
            --environment "$ENV" \
            --role "${RESOURCE_ROLE}" \
            --description "$DESC" \
            || exit 1

        # check if lambda is done with previous step
        checkAndWait || exit 1

        # now publish
        # take version from returnhttps://stackoverflow.com/questions/1955505/parsing-json-with-unix-tools
        # set the variable to code_version https://stackoverflow.com/questions/4651437/how-do-i-set-a-variable-to-the-output-of-a-command-in-bash
        LambdaCodeVersion=$(aws lambda publish-version --function-name "$FNAME" | jq -r '.Version')


    else
        echo "not a new function. but not an old function. this line should not be hit." >&2
    fi

    if [ -n $LambdaCodeVersion ]
    then
        # check if lambda is done with previous step
        checkAndWait || exit 1

        echo "creating/updating alias of $ALIAS locking into version: $LambdaCodeVersion" >&2

        if aws lambda get-alias --function-name $FNAME --name "$ALIAS" || exit 1; then

            echo "alias already exists, updating" >&2

            aws lambda update-alias \
                --function-name $FNAME \
                --name "$ALIAS" \
                --function-version "$LambdaCodeVersion" \
                || exit 1
        else

            echo "alias does not exist, creating" >&2

            aws lambda create-alias \
                --function-name $FNAME \
                --name "$ALIAS" \
                --function-version "$LambdaCodeVersion" \
                || exit 1
        fi
    else
        echo "ERROR: There was an issue deploying and publishing lambda. No lambda code version created." >&2
        exit 1
    fi

}

cleanUpArtifacts() {
    rm -rf lambda_deployment_package
    rm function.zip
}


UPLOADED_FILE_VERSION_ID=""

uploadFileToS3() {

    # $1 is the parameter passed that is a path to the file
    s3ObjectVersionID=$(aws s3api put-object --body $1 --bucket "${S3_BUCKET_FOR_DEPLOYMENT}" --key "${FNAME}/function.zip" | jq -r '.VersionId' )
    if [ -n $s3ObjectVersionID ]
    then
        # use this to "return" the value.
        # https://superuser.com/questions/1320691/print-echo-and-return-value-in-bash-function
        UPLOADED_FILE_VERSION_ID=$s3ObjectVersionID
    else
        echo "There was an issue uploading to s3 and returning object Version ID" >&2
        exit 1
    fi

}


echo "beginning deployment script" >&2

echo "installing requirements.txt" >&2
mkdir lambda_deployment_package
cd lambda_deployment_package

# install s3fs seperately because the dependencies are already in the lamdba env
# pip install --no-deps --no-cache-dir --compile s3fs --target .
pip install --no-cache-dir --compile -r ../requirements.txt --target .


echo "zipping deployment package" >&2
# rsync is like cp, but more options for excluding files and directories
rsync -av --exclude=lambda_deployment_package --exclude=.git --exclude=function.zip --exclude=CI --exclude=.gitignore --exclude=setup.py --exclude=tox.ini --exclude=deployment-config.ini --exclude=README.md --exclude=*.pyc --exclude=__pycache__/* --exclude=event.json --exclude=requirements.txt ../ .
zip -r9 ../function.zip .
cd ../

# get handler file name from $HANDLER variable
IFS='.' read -r HANDLER_FILE_NAME string <<< "$HANDLER"

echo "Handler Name $HANDLER_FILE_NAME" >&2

# assumes its a .py # TODO, dynamic determine or wild-card
zip -g function.zip "$HANDLER_FILE_NAME.py"

if uploadFileToS3 function.zip
then
    echo "successfully uploaded code to s3." >&2
else
    echo "ERROR: failed to upload code to s3." >&2
    exit 1
fi


if deployLambdaFunctionWithCheckIfNew $ISNEW $UPLOADED_FILE_VERSION_ID
then
    echo "successfully deployed lambda function." >&2
else
    echo "ERROR: failed to deploy lambda function." >&2
    exit 1
fi

if cleanUpArtifacts
then
    echo "successfully cleaned up deployment artifacts." >&2
else
    echo "WARNING: there weas an issue cleaning up deployment artifacts." >&2
fi

