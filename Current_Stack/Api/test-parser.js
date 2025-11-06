const fs = require('fs');
const { parseRunWorkbook } = require('./dist/lib/run-import-parser.js');

// Read Excel file
const workbookBuffer = fs.readFileSync('./638976300316473943 copy 5.xlsx');

try {
  const result = parseRunWorkbook(workbookBuffer);
  
  if (result.run && result.run.pickEntries.length > 0) {
    // Group by category to see distribution
    const categoryCounts = {};
    const skuCounts = {};
    
    result.run.pickEntries.forEach(entry => {
      const category = entry.coilItem.sku.category || 'UNCATEGORIZED';
      const skuCode = entry.coilItem.sku.code;
      
      categoryCounts[category] = (categoryCounts[category] || 0) + 1;
      skuCounts[skuCode] = (skuCounts[skuCode] || 0) + 1;
    });
    
    console.log('Category distribution:');
    Object.entries(categoryCounts).forEach(([cat, count]) => {
      console.log(`  ${cat}: ${count}`);
    });
    
    console.log('\nUnique SKUs:', Object.keys(skuCounts).length);
    console.log('Total pick entries:', result.run.pickEntries.length);
    
    // Show some examples of categorized vs uncategorized
    const categorized = result.run.pickEntries.filter(e => e.coilItem.sku.category && e.coilItem.sku.category !== 'UNCATEGORIZED');
    const uncategorized = result.run.pickEntries.filter(e => !e.coilItem.sku.category || e.coilItem.sku.category === 'UNCATEGORIZED');
    
    console.log('\nCategorized items:', categorized.length);
    console.log('Uncategorized items:', uncategorized.length);
    
    if (categorized.length > 0) {
      console.log('\nSample categorized items:');
      categorized.slice(0, 5).forEach((entry, index) => {
        console.log(`  ${index + 1}. ${entry.coilItem.sku.code} - ${entry.coilItem.sku.name} -> ${entry.coilItem.sku.category}`);
      });
    }
    
    if (uncategorized.length > 0) {
      console.log('\nSample uncategorized items:');
      uncategorized.slice(0, 5).forEach((entry, index) => {
        console.log(`  ${index + 1}. ${entry.coilItem.sku.code} - ${entry.coilItem.sku.name}`);
      });
    }
  }
} catch (error) {
  console.error('Parse error:', error.message);
  console.error(error.stack);
}