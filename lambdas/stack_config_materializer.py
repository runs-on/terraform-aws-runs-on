import boto3
from botocore.exceptions import ClientError


secrets = boto3.client("secretsmanager")


def handler(event, context):
    secret_id = event["secret_id"]
    secret_string = event["secret_string"]
    client_request_token = event["client_request_token"]

    try:
        response = secrets.put_secret_value(
            SecretId=secret_id,
            SecretString=secret_string,
            ClientRequestToken=client_request_token,
        )
        return {"version_id": response["VersionId"]}
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ResourceExistsException":
            return {"version_id": client_request_token}
        raise
