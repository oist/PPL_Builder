#! python3
import os
import requests
import json
import re
import itertools
import pathlib
import copy
import datetime

user_header = {'Authorization': 'token ' + os.environ['GITHUB_RELEASE_TOKEN']};
request_timeout = 5

def get_api_url(relRepoUrl, tail):
	return "https://api.github.com/repos/" + relRepoUrl + tail

def post_req(url, payload):
	r = requests.post(
		url,
		headers = user_header,
		data = json.dumps(payload),
		timeout = request_timeout
	)
	return r

def form_tag_payload(tag_name, body, sha):
	# 'YYYY-MM-DDTHH:MM:SSZ (ISO 8601)'
	dateNow = datetime.datetime.utcnow().replace(microsecond=0).isoformat()+'Z'
	# '40 characters and contain only [0-9a-f].'
	return {
		'tag': tag_name,
		'message': body,
		'object': sha,
		'type': 'commit',
		'tagger': {
			'name': 'ChakrabortyUnit',
			'email': '35588569+ChakrabortyUnit@users.noreply.github.com',
			'date': dateNow
		},
	}

def form_release_payload(tag_name, releaseNotes, draft_only = False):
	''' The release name is formed based on the tag_name value.
	The tag_name should be 4 numeric values (i.e. it includes the build info).
	The release_name should be of form MAJOR.MINOR.PATCH, without the BUILD information.
	'''
	release_name = re.match(r'(\d+\.\d+\.\d+)\.\d', tag_name).group(1)
	payload = { 'tag_name': tag_name, 'name': release_name, 'body': releaseNotes }
	# target_commitish defaults to 'master', which specifies what the tag should
	# point to.
	if draft_only:
		payload['draft'] = True
	draft = "draft " if draft_only else ""
	print(f"Forming a {draft}release \"{release_name}\" with tag \"{tag_name}\", description: \"{releaseNotes}\"")
	return payload

def push_release(relRepoUrl, payload):
	''' This function creates a release based on the payload
	that is passed via argument, and returns the upload_url if
	successful.
	It will raise an exception if the POST request is unsuccessful.
	'''
	post_url = get_api_url(relRepoUrl, "/releases")
	print(payload)
	r = post_req(post_url, payload)
	if r.status_code != 201:
		# Some unexpected response...
		print("uh-oh! Response: " + str(r.status_code))
		if r.status_code == 422:
			msg = ('This error code can occur when the target tag (' 
				+ f"{payload['tag_name']}) already exists in the repository.")
			print(msg)
		r.raise_for_status()
	return r.json()['upload_url']

def upload_asset(upload_url, item, label = None):
	''' This function takes a file item and an upload url as a URI template
	and uploads the	file with the same name, and an optional label.
	upload_url is like "https://uploads.github.com/repos/octocat/Hello-World/releases/1/assets{?name,label}"
	'''
	base_upload_url = upload_url.replace('{?name,label}')
	
	item_name = pathlib.Path(item.name).name
	full_url = base_upload_url + '?name=' + item_name
	
	if label: # Only add the label field if a label was passed.
		full_url = full_url + '&label=' + label
	print(full_url)
	
	# Add the necessary Content-Type to the headers
	asset_header = copy.deepcopy(user_header)
	asset_header['Content-Type'] = 'application/octet-stream'

	# Open the file in binary mode to upload.
	file_binary = item.read()
	r = requests.post(
		full_url,
		headers = asset_header,
		data = file_binary,
		timeout = request_timeout
	)
	r.raise_for_status()

def push_tag(relRepoUrl, tag_name, sha, description):
	tag_payload = form_tag_payload(tag_name, description, sha)
	tag_url = get_api_url(relRepoUrl, "/git/tags")
	print(tag_url)
	print(tag_payload)
	print(sha)
	print(description)
	print(tag_name)
	r = post_req(tag_url, tag_payload)
	r.raise_for_status()
	
	# get the new sha for the (annotated) tag that was just created
	tag_sha = r.json()['sha']
	# add or update a reference to that new tag.
	ref_payload = { "ref": "refs/tags/" + tag_name, "sha": tag_sha }
	ref_url = get_api_url(relRepoUrl, "/git/refs")
	try:
		# create a new reference to the new tag object.
		r = post_req(ref_url, ref_payload)
		r.raise_for_status()
	except requests.exceptions.HTTPError as err:
		print(f"git tag {tag_name} already exists. updating the reference")
		patch_payload = { 'sha': tag_sha, 'force': false }
		r = requests.patch(
			ref_url + f"/tags/{tag_name}",
			headers = user_header,
			data = json.dumps(patch_payload),
			timeout = request_timeout
		)
		r.raise_for_status()
	print(f"added a tag \"{tag_name}\" with description: \"{description}\"")

def process_release(relRepoUrl, tag_name, releaseNotes, files):
	payload = form_release_payload(tag_name, releaseNotes)
	upload_url = push_release(relRepoUrl, payload)
	if len(files) != 0:
		label = None
		for filepath in files:
			asset = open(filepath, 'rb')
			upload_asset(upload_url, asset, label)

if __name__ == "__main__":
	possibleUrls = []
	keyBasename = 'GO_MATERIAL_URL'
	for (key, value) in os.environ.items():
		if key.startswith(keyBasename):
			possibleUrls.append({key: value})
	if len(possibleUrls) != 1:
		raise KeyError('A unique material URL was not found - found ' + str(possibleUrls))
	print(possibleUrls)
	# repositoryUrl is like 'git@github.com:oist/Chakraborty_library-name'
	keyName, repositoryUrl = [(k, v) for k, v in possibleUrls[0].items()][0]
	# relativeRepoUrl is like 'oist/Chakraborty_library-name'
	relativeRepoUrl = re.search(r":(.*/.*)(\.git)?", repositoryUrl).groups()[0]
	specificName = re.search(keyBasename + r"(_?.*)", keyName).groups()[0]
	revisionHash = os.environ['GO_REVISION' + specificName] # No leading 'g'
	print(relativeRepoUrl)
	print(revisionHash)
	# Should be defined, but use "get" rather than "['..']" to avoid a KeyError.
	releaseNotes = os.environ.get('RELEASE_NOTES', '') # Default to none, but should be defined.
	
	# Need a target version, and list of files
	targetDirs = [os.path.join('artifacts', d) for d in os.listdir('artifacts')]
	print(targetDirs)
	
	# The artifacts are fetched into 'artifacts/{target}/{GO_PIPELINE_NAME}/...'
	artifactPathName = os.environ['PPL_Name']
	fileDict = {}
	for d in targetDirs:
		fileDict[d] = os.listdir(os.path.join(d, artifactPathName))
	# {'artifacts/Windows_32_Debug': [
	#   'oist-name_windows32_debug_1.2.3.4_windows_all.nipkg',
	#   'oist-name_windows32_debug_1.2.3.4_windows_all.nipkg.sig',
	#   'name.lvlibp'
	#  ], ...}
	
	# This includes the .sig files
	nipkgList = [f for f in itertools.chain.from_iterable(fileDict.values()) if f[-6:] != 'lvlibp']
	foundVersions = set()
	versionPattern = re.compile(r".*(([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)).*")
	for f in nipkgList:
		m = versionPattern.match(f)
		if m != None:
			foundVersions.add(m.groups())
	if len(foundVersions) != 1:
		raise RuntimeError('The number of versions parsed from the files to be released was not equal to 1: ' + str(foundVersions))
	(version, major, minor, patch, build) = list(foundVersions)[0]
	
	# Push a tag for the built commit
	push_tag(relativeRepoUrl, version, revisionHash, releaseNotes)
	filesToUpload = []
	process_release(relativeRepoUrl, version, releaseNotes, filesToUpload)