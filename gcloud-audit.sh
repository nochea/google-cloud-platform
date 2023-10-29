#!/bin/sh

usage() {
  cat<<EOF
Usage: 

Launch this script after you chmoded +x it 
./gcloud-audit.sh

gcloud-audit.sh will output a csv file containing various info about your GCP Projects
Since it is difficult to check whether a gcp project is active or not, this script may
help you determine if it is the case. You will get a csv file containing follwing info
 * Project ID
 * Creation date
 * Billing status and Billing account if billing is active
 * A list of associated owners
 * Project utilization from recommender API
 

EOF
  exit
}

while getopts ":h" opt; do
  case ${opt} in
    h|?) usage ;;
  esac
done


now=$(date +"%y.%m.%d-%H:%M:%S")
output="${now}_gcp-audit.csv"
role="roles/owner"


echo "Project ID;Created on;Billing Status;Billing Account;Owner;Project Rank"  > $output

for project_id in $(gcloud projects list --format="value(projectId)"); do
  if [[ ! "$project_id" == sys-* ]] 
    then
	# Retrieve creation time
        created_on=$(
	gcloud projects describe $project_id \
	  --format="value(createTime)")
        
	# Retrive Billing status
	billing=$(gcloud beta billing projects describe $project_id)
        
	billing_status=$(echo "$billing" | grep "billingEnabled:" | cut -c16- )
        if [[ "$billing_status" =~ 'true' ]]
        then 
            billing_account=$(echo "$billing" | grep "billingAccountName:" | cut -c37-)
        else
            billing_account="N/A"
        fi
	
	# Retrieve owners
        owners=$(
	gcloud projects get-iam-policy $project_id \
	  --flatten="bindings[].members[]" \
          --filter="bindings.role=$role" \
	  --format="value(bindings.members)")
        pretty_owners="${owners//$'\n'/,}"
	
	# Retrieve recommender API percentile usage
	# Activate recommender API if not enabled
	recommender_api_status=$(
	gcloud services list \
	--enabled \
	--project=$project_id | grep "recommender" | cut -c1-26)

	if [[ "$recommender_api_status" != 'recommender.googleapis.com' ]]
	then 
	    `gcloud services enable recommender.googleapis.com --project=$project_id`
	fi 
	
	utilization_insight=$(
	gcloud recommender insights list \
	  --project=$project_id \
	  --location=global \
	  --insight-type=google.resourcemanager.projectUtilization.Insight \
	  --format="value(DESCRIPTION)" | cut -c34-49 )

	if [ -z "$utilization_insight" ]
	then
	utilization_insight="No metrics available"
	fi
 
	# Send all variable to output, with csv compatible separators
	echo "$project_id;$created_on;$billing_status;$billing_account;$pretty_owners;$utilization_insight">> $output
  fi 
done
