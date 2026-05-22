import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
sns = boto3.client('sns')

BUCKET_NAME = os.environ['BUCKET_NAME']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']


def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        event_name = body['event_name']
        event_date = body['event_date']
        event_description = body['event_description']

        response = s3.get_object(Bucket=BUCKET_NAME, Key='events.json')
        events_data = json.loads(response['Body'].read().decode('utf-8'))

        new_event = {
            'id': len(events_data['events']) + 1,
            'name': event_name,
            'date': event_date,
            'description': event_description,
            'created_at': datetime.now().isoformat()
        }
        events_data['events'].append(new_event)

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key='events.json',
            Body=json.dumps(events_data, indent=2),
            ContentType='application/json'
        )

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=f"New Event: {event_name}\nDate: {event_date}\nDescription: {event_description}",
            Subject=f'New Event: {event_name}'
        )

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'message': 'Event created successfully', 'event': new_event})
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
