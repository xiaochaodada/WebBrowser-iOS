const {execSync} = require('child_process')
const fs = require('fs-extra')
const path = require('path')
const ppconfig = require('./ppconfig.json')
const projectName = "webBrowser";

const updateAppName = async (appName) => {
    // workerflow build app showName
    try {
        let plistPath = path.join(__dirname, `../${projectName}/Info.plist`)
        execSync(
            `plutil -replace CFBundleDisplayName -string "${appName}" "${plistPath}"`
        )
        execSync(
            `plutil -replace CFBundleExecutable -string "${projectName}" "${plistPath}"`
        )
        // execSync(
        //     `plutil -replace CFBundleName -string "${appName}" "${plistPath}"`
        // )
        console.log(`✅ Updated app_name to: ${appName}`)
    } catch (error) {
        console.error('❌ Error updating app name:', error)
    }
}


const updateConfig = async (debug, webUrl, webview) => {
    try {
        // Assuming ContentView.swift
        const contentViewPath = path.join(
            __dirname,
            `../${projectName}/ContentView.swift`
        )
        let content = await fs.readFile(contentViewPath, 'utf8')
        // 判断debug是否为true
        content = content.replace(
            /static let debug = true/,
            `static let debug = false`
        )
        if (debug) {
            //将 static let debug = false 替换为 static let debug = true
            content = content.replace(
                /static let debug = false/,
                `static let debug = ${debug}`
            )
            console.log(`✅ Updated web debug to: ${debug}`)
        }
        const {userAgent} = webview
        content = content.replace(
            /static let customUserAgent = ".*?"/,
            `static let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"`
        )
        if (userAgent) {
            // static let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            // ""是自定义的
            content = content.replace(
                /static let customUserAgent = ".*?"/,
                `static let customUserAgent = "${userAgent}"`
            )
            console.log(`✅ Updated web userAgent to: ${userAgent}`)
        }

        //替换 static let openUrl = "https://www.baidu.com"
        if (webUrl) {
            content = content.replace(
                /static let openUrl = ".*?"/,
                `static let openUrl = "${webUrl}"`
            )
            console.log(`✅ Updated web URL to: ${webUrl}`)
        }
        await fs.writeFile(contentViewPath, content)
    } catch (error) {
        console.error('❌ Error updating web URL:', error)
    }
}
// set github env
const setGithubEnv = (name, version, pubBody) => {
    console.log('setGithubEnv......')
    const envPath = process.env.GITHUB_ENV
    if (!envPath) {
        console.error('GITHUB_ENV is not defined')
        return
    }
    try {
        const entries = {
            NAME: name,
            VERSION: version,
            PUBBODY: pubBody,
        }
        for (const [key, value] of Object.entries(entries)) {
            if (value !== undefined) {
                fs.appendFileSync(envPath, `${key}=${value}\n`)
            }
        }
        console.log('✅ Environment variables written to GITHUB_ENV')
        console.log(fs.readFileSync(envPath, 'utf-8'))
    } catch (err) {
        console.error('❌ Failed to parse config or write to GITHUB_ENV:', err)
    }
    console.log('setGithubEnv success')
}

// update android applicationId
const updateBundleId = async (newBundleId) => {
    // Write back only if changes were made
    const pbxprojPath = path.join(
        __dirname,
        `../${projectName}.xcodeproj/project.pbxproj`
    )
    try {
        console.log(`Updating Bundle ID to ${newBundleId}...`)
        let content = fs.readFileSync(pbxprojPath, 'utf8')
        content = content.replaceAll(
            /PRODUCT_BUNDLE_IDENTIFIER = (.*?);/g,
            `PRODUCT_BUNDLE_IDENTIFIER = ${newBundleId};`
        )
        fs.writeFileSync(pbxprojPath, content)
        console.log(`✅ Updated Bundle ID to: ${newBundleId} success`)
    } catch (error) {
        console.error('Error updating Bundle ID:', error)
    }
}

const main = async () => {
        const {webview} = ppconfig.phone
        const {name, showName, version, webUrl, id, pubBody, debug} = ppconfig.ios

        // Update app name if provided
        await updateAppName(showName)

        // 更新配置信息
        await updateConfig(debug, webUrl, webview)

        // update android applicationId
        await updateBundleId(id)

        // set github env
        setGithubEnv(name, version, pubBody)

        // success
        console.log('✅ Worker Success')
    }

// run
;(async () => {
    try {
        console.log('🚀 worker start')
        await main()
        console.log('🚀 worker end')
    } catch (error) {
        console.error('❌ Worker Error:', error)
    }
})()
