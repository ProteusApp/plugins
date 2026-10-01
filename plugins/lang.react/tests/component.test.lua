local component = require ('lib.component') --[[@as LangReact.ComponentModule]]

test ('problem explains a name a component cannot have', function ()
  eq (component.problem ('Button'), nil)
  eq (component.problem ('Nav_Bar2'), nil)
  eq (component.problem (''), 'Type a name, such as Button.')
  eq (
    component.problem ('button'),
    'A component name starts with a capital letter.'
  )
  eq (
    component.problem ('My Button'),
    'A component name holds only letters, digits and _.'
  )
end)

test ('name_of takes the name from the file', function ()
  eq (component.name_of ('C:/app/src/Button.tsx'), 'Button')
  eq (component.name_of ([[C:\app\src\Card.test.tsx]]), 'Card')
  eq (component.name_of ('src/index.jsx'), 'Component')
end)

test ('source types the props of a TypeScript component', function ()
  eq (
    component.source ('Button', true),
    table.concat ({
      'type ButtonProps = {',
      '  className?: string;',
      '};',
      '',
      'export function Button({ className }: ButtonProps) {',
      '  return <div className={className}>Button</div>;',
      '}',
      '',
    }, '\n')
  )
  eq (
    component.source ('Card', false),
    'export function Card({ className }) {\n'
      .. '  return <div className={className}>Card</div>;\n}\n'
  )
end)
