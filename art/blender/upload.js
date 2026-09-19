// Uploads a file to Roblox through Open Cloud (group-owned) and waits for its asset id.
// usage: node upload.js <file> <Model|Decal> <displayName>
const fs = require('fs');
const path = require('path');
const KEY = process.env.ROBLOX_OPEN_CLOUD_API_KEY;
const GROUP = '506801379';
const [, , file, assetType, displayName] = process.argv;
const TYPES = { '.fbx': 'model/fbx', '.png': 'image/png' };

async function main() {
	if (!KEY) throw new Error('no api key in env');
	const form = new FormData();
	form.append('request', JSON.stringify({
		assetType,
		displayName: displayName.slice(0, 50),
		description: '1000 Hidden Objects game art',
		creationContext: { creator: { groupId: GROUP } },
	}));
	const data = fs.readFileSync(file);
	form.append('fileContent', new Blob([data], { type: TYPES[path.extname(file).toLowerCase()] }), path.basename(file));
	let res = await fetch('https://apis.roblox.com/assets/v1/assets', { method: 'POST', headers: { 'x-api-key': KEY }, body: form });
	let body = await res.json().catch(() => ({}));
	if (!res.ok) throw new Error('upload ' + res.status + ' ' + JSON.stringify(body));
	const op = body.path || ('operations/' + body.operationId);
	for (let i = 0; i < 40; i++) {
		await new Promise(r => setTimeout(r, 1500));
		res = await fetch('https://apis.roblox.com/assets/v1/' + op, { headers: { 'x-api-key': KEY } });
		body = await res.json().catch(() => ({}));
		if (body.done) {
			if (body.response && body.response.assetId) {
				console.log(JSON.stringify({ file: path.basename(file), assetId: body.response.assetId, moderation: body.response.moderationResult }));
				return;
			}
			throw new Error('failed ' + JSON.stringify(body));
		}
	}
	throw new Error('timeout ' + JSON.stringify(body));
}
main().catch(e => { console.error(String(e.message || e)); process.exit(1); });
