import boto3
import json
import sys
import traceback


def get_azs(region=None):
    ec2_local = boto3.client('ec2', region_name=region)
    azs_list_of_dicts_response = ec2_local.describe_availability_zones()['AvailabilityZones']
    azs_list = []
    for az in azs_list_of_dicts_response:
        azs_list.append(az["ZoneName"])
    return azs_list


def get_regions():
    ec2 = boto3.client('ec2', region_name="us-east-1")
    filename = "data/RegionData.json"
    try:
        with open(filename, 'r') as infile:
            return json.load(infile)
    except:
        regions = ec2.describe_regions()
        del regions['ResponseMetadata']
        for region in regions["Regions"]:
            region["AvailabilityZones"] = get_azs(region["RegionName"])
            del region['Endpoint']
            del region['OptInStatus']
        with open(filename, 'w') as outfile:
            json.dump(regions, outfile, indent=4)
        return regions


def get_region_from_az(az=None):
    region_data = get_regions()
    for region in region_data["Regions"]:
        if az in region["AvailabilityZones"]:
            region["SpecifiedAz"] = az
            return region

    sys.exit("AZ does not exist.")


def cloudformation_deploy(namespace=None, cf_stack=None, region_name=None):
    client = boto3.client('cloudformation', region_name=region_name)

    def create_stack(client, namespace, cf_stack):
        try:
            response = client.create_stack(
                StackName=namespace,
                TemplateBody=json.dumps(cf_stack, indent=4),
            )
            return response['StackId']
        except Exception:
            traceback.print_exc()
            return None

    def wait_for_create_stack_complete(client, stack_id):
        waiter = client.get_waiter('stack_create_complete')
        waiter.wait(StackName=stack_id)
        return stack_id

    def get_first_failure_event(stack_id):
        try:
            response = client.describe_stack_events(StackName=stack_id)
            sorted_events = sorted(response['StackEvents'], key=lambda x: x['Timestamp'])
            for event in sorted_events:
                if 'FAIL' in event['ResourceStatus']:
                    return event
        except Exception as e:
            print("An error occurred while retrieving creation events:", e)

        return None

    stack_id = create_stack(client, namespace, cf_stack)
    if not stack_id:
        return

    try:
        wait_for_create_stack_complete(client, stack_id)
    except Exception as e:
        print("Create stack failed:")
        traceback.print_exc()
        failure_event = get_first_failure_event(stack_id)
        if failure_event:
            if "ResourceStatusReason" in failure_event and "ResourceStatusReason" in failure_event:
                print("CREATE_FAILED reason:", failure_event["ResourceStatusReason"])
            else:
                print("First failure event:\n", json.dumps(failure_event, indent=4))
        else:
            print("No failure events found.")
        return None

    return stack_id


def get_cloudformation_blob(namespace, region_name):
    client = boto3.client('cloudformation', region_name=region_name)
    response = client.list_stack_resources(
        StackName=namespace
    )
    return response


def get_instances_from_cf_resources(namespace=None, region_name=None):
    def get_instances_data(instances, region_name):
        ec2_local = boto3.client('ec2', region_name=region_name)
        response = ec2_local.describe_instances(
            InstanceIds=instances)
        return response

    def convert_tags_to_dicts(tags):
        output_dict = {}
        for tag in tags:
            output_dict[tag["Key"]] = tag["Value"]
        return output_dict

    def squidge_instances_data(namespace, region_name):

        def get_boto_instance(instance_id, region_name):
            ec2_local = boto3.resource('ec2', region_name=region_name)
            return ec2_local.Instance(instance_id)

        instances_instance_list = []
        cf_data = get_cloudformation_blob(namespace, region_name)
        for resource in cf_data["StackResourceSummaries"]:
            if resource["ResourceType"] == "AWS::EC2::Instance":
                instances_instance_list.append(get_boto_instance(resource['PhysicalResourceId'], region_name))
        # returns a list of boto3 instance objects.
        # https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/instance/index.html
        return instances_instance_list

    def filter_instance_by_role_key(instances_list, role):
        return list(
            filter(lambda instance: any(tag['Key'] == 'Role' and tag['Value'] == role for tag in instance.tags or []),
                   instances_list)
        )

    instances_list = squidge_instances_data(namespace, region_name)

    instances_dict_of_lists = {}
    instances_dict_of_lists["all_instances"] = instances_list
    instances_dict_of_lists["storage"] = filter_instance_by_role_key(instances_list, "storage")
    instances_dict_of_lists["management"] = filter_instance_by_role_key(instances_list, "management")
    instances_dict_of_lists["kubernetes"] = filter_instance_by_role_key(instances_list, "kubernetes")

    return instances_dict_of_lists
