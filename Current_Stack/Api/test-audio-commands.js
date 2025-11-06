// Test script to verify audio commands ordering
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function testAudioCommands() {
  console.log('Testing audio commands ordering...');
  
  // Get pick entries that need to be packed, ordered by location, then machine, then coil (largest to smallest)
  const pickEntries = await prisma.pickEntry.findMany({
    where: {
      status: 'PENDING',
      count: { gt: 0 }
    },
    include: {
      coilItem: {
        include: {
          coil: {
            include: {
              machine: {
                include: {
                  location: true,
                  machineType: true
                }
              }
            }
          },
          sku: true
        }
      }
    },
    orderBy: [
      { coilItem: { coil: { machine: { location: { name: 'asc' } } } } },
      { coilItem: { coil: { machine: { code: 'asc' } } } },
      { count: 'desc' }, // Largest count first (largest coil)
      { coilItem: { coil: { code: 'asc' } } },
      { coilItem: { sku: { name: 'asc' } } }
    ]
  });

  console.log(`Found ${pickEntries.length} pick entries`);
  
  // Group by location and machine to create audio commands
  const audioCommands = [];

  // Track unique locations and machines to avoid duplicates
  const uniqueLocations = new Set();
  const uniqueMachines = new Set();

  // Group entries by location and machine
  const groupedEntries = pickEntries.reduce((acc, entry) => {
    const location = entry.coilItem.coil.machine.location;
    const machine = entry.coilItem.coil.machine;
    
    const locationKey = location?.id || 'no-location';
    const machineKey = machine?.id || 'no-machine';
    
    if (!acc[locationKey]) {
      acc[locationKey] = {
        location: location,
        machines: {}
      };
    }
    
    if (!acc[locationKey].machines[machineKey]) {
      acc[locationKey].machines[machineKey] = {
        machine: machine,
        entries: []
      };
    }
    
    acc[locationKey].machines[machineKey].entries.push(entry);
    return acc;
  }, {});

  // Generate audio commands in the correct order
  Object.values(groupedEntries).forEach(locationGroup => {
    // Add location announcement
    const location = locationGroup.location;
    const locationKey = location?.id || 'no-location';
    if (location && !uniqueLocations.has(locationKey)) {
      uniqueLocations.add(locationKey);
      audioCommands.push({
        id: `location-${locationKey}`,
        audioCommand: `Location ${location.name || 'Unknown'}`,
        pickEntryId: '',
        type: 'location',
        locationName: location.name || 'Unknown',
        count: 0
      });
    }
    
    // Add machine announcements and items for each machine in this location
    Object.values(locationGroup.machines).forEach(machineGroup => {
      const machine = machineGroup.machine;
      const machineKey = machine?.id || 'no-machine';
      
      // Add machine announcement
      if (machine && !uniqueMachines.has(machineKey)) {
        uniqueMachines.add(machineKey);
        audioCommands.push({
          id: `machine-${machineKey}`,
          audioCommand: `Machine ${machine.code || machine.description || 'Unknown'}`,
          pickEntryId: '',
          type: 'machine',
          machineName: machine.code || machine.description || 'Unknown',
          count: 0
        });
      }
      
      // Add item announcements (already sorted by count descending for largest to smallest)
      machineGroup.entries.forEach(entry => {
        const sku = entry.coilItem.sku;
        const coil = entry.coilItem.coil;
        
        if (sku) {
          const count = entry.count;
          const skuName = sku.name || 'Unknown item';
          const skuCode = sku.code || '';
          const coilCode = coil.code || '';
          
          // Build audio command similar to RunDaddy app
          let audioCommand = `${skuName}`;
          if (sku.type && sku.type.trim()) {
            audioCommand += `, ${sku.type}`;
          }
          audioCommand += `. Need ${count}`;
          if (coilCode) {
            audioCommand += `. Coil ${coilCode}`;
          }
          
          audioCommands.push({
            id: entry.id,
            audioCommand: audioCommand,
            pickEntryId: entry.id,
            type: 'item',
            machineName: machine?.code || machine?.description || 'Unknown',
            skuName: skuName,
            skuCode: skuCode,
            count: count,
            coilCode: coilCode
          });
        }
      });
    });
  });

  console.log('\nAudio Commands:');
  audioCommands.forEach((cmd, index) => {
    console.log(`${index + 1}. [${cmd.type}] ${cmd.audioCommand}`);
  });
  
  console.log(`\nTotal items: ${audioCommands.filter(cmd => cmd.type === 'item').length}`);
  console.log(`Has items: ${audioCommands.some(cmd => cmd.type === 'item')}`);
}

testAudioCommands()
  .catch(console.error)
  .finally(() => prisma.$disconnect());