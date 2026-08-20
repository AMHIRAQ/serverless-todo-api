import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def handler(event, context):
    user_id = event['requestContext']['authorizer']['claims']['sub']
    todo_id = event['pathParameters']['todoId']

    table.delete_item(Key={'userId': user_id, 'todoId': todo_id})

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'message': 'Deleted'})
    }