import json
import uuid
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def handler(event, context):
    body = json.loads(event['body'])
    user_id = event['requestContext']['authorizer']['claims']['sub']

    todo_id = str(uuid.uuid4())

    item = {
        'userId': user_id,
        'todoId': todo_id,
        'title': body['title'],
        'completed': False
    }

    table.put_item(Item=item)

    return {
        'statusCode': 201,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(item)
    }