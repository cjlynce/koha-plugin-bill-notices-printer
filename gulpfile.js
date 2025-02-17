const gulp = require('gulp');
const release = require('gulp-github-release');
const fs = require('fs');
const run = require('gulp-run');

var package_json = JSON.parse(fs.readFileSync('./package.json'));
var release_filename = package_json.name + '-v' + package_json.version + '.kpz';

var pm_file = 'PatronBillNotices.pm';
var pm_file_path = 'Koha/Plugin/Org/WestlakeLibrary/';
var pm_file_path_full = pm_file_path + pm_file;
var pm_file_path_dist = 'dist/' + pm_file_path;
var pm_file_path_full_dist = pm_file_path_dist + pm_file;

console.log(release_filename);
console.log(pm_file_path_full_dist);

gulp.task('build', () => {
    run('mkdir dist ; cp -ar Koha dist/. ; sed -i -e "s/{VERSION}/' + package_json.version + '/g" ' + pm_file_path_full_dist + ' ; cd dist ; zip -r ../' + release_filename + ' ./Koha ; cd .. ; rm -rf dist').exec();

});

gulp.task('release', () => {
    gulp.src(release_filename)
        .pipe(release({
            manifest: require('./package.json') // package.json from which default values will be extracted if they're missing
        }));
});
