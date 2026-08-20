import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def handler(event, context):
    user_id = event['requestContext']['authorizer']['claims']['sub']
    todo_id = event['pathParameters']['todoId']
    body = json.loads(event['body'])

    table.update_item(
        Key={'userId': user_id, 'todoId': todo_id},
        UpdateExpression='SET completed = :c',
        ExpressionAttributeValues={':c': body['completed']}
    )

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'message': 'Updated'})
    }