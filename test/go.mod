module github.com/sjysngh/runs-on-tf/test

go 1.21

require (
	github.com/gruntwork-io/terratest v0.46.8
	github.com/stretchr/testify v1.8.4
	github.com/aws/aws-sdk-go-v2 v1.24.0
	github.com/aws/aws-sdk-go-v2/config v1.26.1
	github.com/aws/aws-sdk-go-v2/service/s3 v1.47.5
	github.com/aws/aws-sdk-go-v2/service/dynamodb v1.26.6
	github.com/aws/aws-sdk-go-v2/service/sqs v1.29.5
	github.com/aws/aws-sdk-go-v2/service/ec2 v1.141.0
	github.com/aws/aws-sdk-go-v2/service/efs v1.26.5
	github.com/aws/aws-sdk-go-v2/service/ecr v1.24.5
)
