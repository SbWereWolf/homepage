import {access, cp, mkdir, mkdtemp, rename, rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.resolve(scriptDir, '..');
const repoDir = path.resolve(projectDir, '..', '..');

const siteName = 'sb-werewolf-2025';
const sourceDir = path.join(projectDir, siteName);
const defaultTargetDir = path.join(repoDir, 'www', 'home', siteName);
const targetDir = process.env.PUBLISH_TARGET_DIR
    ? path.resolve(process.env.PUBLISH_TARGET_DIR)
    : defaultTargetDir;

const allowedTargets = [
    defaultTargetDir,
    path.join(repoDir, 'tmp'),
].map((dir) => path.resolve(dir) + path.sep);

const resolvedTarget = targetDir + path.sep;

if (!allowedTargets.some((allowedTarget) => resolvedTarget.startsWith(allowedTarget))) {
    throw new Error(`Refusing to publish outside allowed directories: ${targetDir}`);
}

const sourceCss = path.join(sourceDir, 'src', siteName + '.css');
const builtCss = path.join(sourceDir, 'src', 'out', siteName + '.css');
const targetParentDir = path.dirname(targetDir);
const targetBackupDir = path.join(
    targetParentDir,
    `.${path.basename(targetDir)}.previous-${process.pid}-${Date.now()}`,
);
const tempRootDir = await mkdtemp(path.join(os.tmpdir(), `${siteName}-publish-`));
const stagingDir = path.join(tempRootDir, siteName);

async function pathExists(filePath) {
    try {
        await access(filePath);
        return true;
    } catch {
        return false;
    }
}

async function buildPublication(targetPublicationDir) {
    const targetSourceCss = path.join(targetPublicationDir, path.relative(sourceDir, sourceCss));
    const targetCss = path.join(targetPublicationDir, 'src', siteName + '.css');
    const targetOutDir = path.join(targetPublicationDir, 'src', 'out');

    await cp(sourceDir, targetPublicationDir, {recursive: true});
    await rm(targetSourceCss, {force: true});
    await cp(builtCss, targetCss);
    await rm(targetOutDir, {recursive: true, force: true});
}

async function verifyPublication(targetPublicationDir) {
    await access(path.join(targetPublicationDir, 'index.html'));
    await access(path.join(targetPublicationDir, 'src', siteName + '.css'));

    if (await pathExists(path.join(targetPublicationDir, 'src', 'out'))) {
        throw new Error(`Unexpected generated output directory in publication: ${targetPublicationDir}`);
    }
}

await mkdir(targetParentDir, {recursive: true});

try {
    await buildPublication(stagingDir);
    await verifyPublication(stagingDir);

    if (await pathExists(targetDir)) {
        await rm(targetBackupDir, {recursive: true, force: true});
        await rename(targetDir, targetBackupDir);
    }

    try {
        await cp(stagingDir, targetDir, {recursive: true});
    } catch (error) {
        await rm(targetDir, {recursive: true, force: true});

        if (await pathExists(targetBackupDir)) {
            await rename(targetBackupDir, targetDir);
        }
        throw error;
    }

    await rm(targetBackupDir, {recursive: true, force: true});
} finally {
    await rm(tempRootDir, {recursive: true, force: true});
}

console.log(`Published ${siteName} to ${path.relative(repoDir, targetDir)}`);
