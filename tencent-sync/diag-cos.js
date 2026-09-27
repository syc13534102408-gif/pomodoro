const fs = require('fs');
const COS = require('cos-nodejs-sdk-v5');
const cred = {};
fs.readFileSync(process.env.HOME + '/.tencentcloud/credentials', 'utf8').split('\n').forEach(line => {
  const m = line.match(/^(TENCENTCLOUD_\w+)=(.+)$/);
  if (m) cred[m[1]] = m[2].trim();
});
const cos = new COS({ SecretId: cred.TENCENTCLOUD_SECRET_ID, SecretKey: cred.TENCENTCLOUD_SECRET_KEY });
const L = [];
cos.getBucket({ Bucket: 'pine-sync-1478270344', Region: 'ap-guangzhou' }, (err, data) => {
  if (err) {
    L.push('❌ 列桶失败: ' + err.statusCode + ' ' + err.code + ' ' + err.message);
    fs.writeFileSync('/tmp/cos-diag.txt', L.join('\n'));
    return;
  }
  L.push('✅ 列桶成功，对象数: ' + ((data.Contents || []).length));
  (data.Contents || []).sort((a, b) => new Date(b.LastModified) - new Date(a.LastModified)).slice(0, 8).forEach(o => {
    L.push('  ' + o.Key + '  ' + o.LastModified + '  ' + o.Size + 'B');
  });
  // 写测试
  cos.putObject({ Bucket: 'pine-sync-1478270344', Region: 'ap-guangzhou', Key: 'diag/write-test.txt', Body: 'ping-' + Date.now() }, (e2) => {
    L.push(e2 ? '❌ 写入失败: ' + e2.statusCode + ' ' + e2.code + ' ' + e2.message : '✅ 写入成功（桶可写）');
    fs.writeFileSync('/tmp/cos-diag.txt', L.join('\n'));
  });
});
