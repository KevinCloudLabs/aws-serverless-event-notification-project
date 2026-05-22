import json
import boto3
import os

s3 = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']


def lambda_handler(event, context):
    try:
        response = s3.get_object(Bucket=BUCKET_NAME, Key='events.json')
        events_data = json.loads(response['Body'].read().decode('utf-8'))

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(events_data)
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
