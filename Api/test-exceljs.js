import pkg from 'exceljs';
const { Workbook } = pkg;

console.log('✅ exceljs import working correctly');
console.log('Workbook constructor:', typeof Workbook);

const workbook = new Workbook();
console.log('✅ Workbook instance created successfully');

process.exit(0);