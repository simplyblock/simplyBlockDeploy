import boto3
import yaml
import json
import sys
import traceback

def get_azs(region):
    ec2_local = boto3.client('ec2', region_name=region)
    azs_list_of_dicts_response = ec2_local.describe_availability_zones()['AvailabilityZones']
    azs_list = []
    for az in azs_list_of_dicts_response:
        azs_list.append(az["ZoneName"])
    return azs_list

def get_regions():
    ec2 = boto3.client('ec2')
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

def get_region_from_az(az):
    region_data = get_regions()
    for region in region_data["Regions"]:
        if az in region["AvailabilityZones"]:
            region["SpecifiedAz"] = az
            return region
        
    
    sys.exit("AZ does not exist.")

def cloudformation_deploy(namespace=None, cf_stack=None, region=None):

    client = boto3.client('cloudformation', region_name=region)
    def createStack(client, namespace, cf_stack):
        try:
            response = client.create_stack(
                StackName=namespace,
                TemplateBody=json.dumps(cf_stack, indent=4),
            )
            return response['StackId']
        except Exception:
            traceback.print_exc()
            return False

    def createWaiter(client, stack_id):
        waiter = client.get_waiter('stack_create_complete')
        waiter.wait(
            StackName=stack_id,
        )
    
        return stack_id
    
    stackId = createStack(client, namespace, cf_stack)
    if stackId:
        createWaiter(client, stackId)

